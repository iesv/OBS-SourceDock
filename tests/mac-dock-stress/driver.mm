// Test-only driver: run the real plugin inside an isolated OBS on native Cocoa.
// The normal release build does not compile this file.
#import <AppKit/AppKit.h>

#include "source-dock.hpp"
#include <obs-module.h>
#include <QAction>
#include <QApplication>
#include <QElapsedTimer>
#include <QFile>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMainWindow>
#include <QPointer>
#include <QSaveFile>
#include <QSysInfo>
#include <QTimer>

class MacDockStress : public QObject {
	QMainWindow *host;
	QDockWidget *pluginDock = nullptr;
	SourceDock *plugin = nullptr;
	QList<QDockWidget *> builtins;
	QElapsedTimer elapsed;
	int cycle = 0;
	int builtin = 0;
	int phase = 0;
	int checks = 0;
	int baselineChecks = 0;
	int tabOcclusions = 0;
	int baselineTabOcclusions = 0;
	bool baseline = true;
	const int cycles = 200;
	QString reportPath;
	bool finished = false;
	QString sourceType;

	QJsonObject state() const
	{
		QJsonArray panels;
		for (auto *dock : host->findChildren<QDockWidget *>()) {
			const auto rect = dock->geometry();
			panels.append(QJsonObject{{"name", dock->objectName()}, {"visible", dock->isVisible()},
				{"hidden", dock->isHidden()}, {"menu_checked", dock->toggleViewAction()->isChecked()},
				{"floating", dock->isFloating()}, {"visible_region_empty", dock->visibleRegion().isEmpty()},
				{"geometry", QJsonArray{rect.x(), rect.y(), rect.width(), rect.height()}}});
		}
		return {{"platform", QGuiApplication::platformName()}, {"os", QSysInfo::prettyProductName()},
			{"architecture", QSysInfo::currentCpuArchitecture()}, {"obs_version", obs_get_version_string()},
			{"qt_version", qVersion()}, {"cycles_completed", cycle}, {"target_cycles", cycles},
			{"source_type", sourceType},
			{"menu_show_checks", checks}, {"baseline_menu_show_checks", baselineChecks},
			{"menu_action_tab_occlusions", tabOcclusions}, {"baseline_tab_occlusions", baselineTabOcclusions},
			{"baseline", baseline}, {"phase", phase}, {"builtin_index", builtin},
			{"modal_widget", QApplication::activeModalWidget() != nullptr},
			{"mouse_grabber", QWidget::mouseGrabber() != nullptr},
			{"keyboard_grabber", QWidget::keyboardGrabber() != nullptr},
			{"elapsed_ms", static_cast<double>(elapsed.elapsed())}, {"docks", panels}};
	}

	void finish(bool success, const QString &reason)
	{
		if (finished)
			return;
		finished = true;
		auto result = state();
		result.insert("success", success);
		result.insert("reason", reason);
		result.insert("scope", "Actual OBS, native Cocoa, programmatic docking, real dock menu actions and explicit selection of tabbed docks, with a plain QWidget dock baseline; physical drag gestures and OS menu clicks are not simulated");
		QSaveFile output(reportPath);
		if (output.open(QIODevice::WriteOnly)) {
			output.write(QJsonDocument(result).toJson());
			output.commit();
		}
		host->grab().save(reportPath + ".png");
		blog(success ? LOG_INFO : LOG_ERROR, "[SourceDockMacStressDriver] %s", reason.toUtf8().constData());
		QTimer::singleShot(100, host, &QWidget::close);
	}

	void step()
	{
		if (finished)
			return;
		if (elapsed.elapsed() > 600000) {
			finish(false, "Native dock stress exceeded its time limit");
			return;
		}
		if (QApplication::activeModalWidget()) {
			finish(false, "An unexpected modal dialog blocks the OBS interface");
			return;
		}
		switch (phase) {
		case 0:
			pluginDock->setFloating(true);
			pluginDock->resize(480, 270);
			pluginDock->show();
			phase = 1;
			break;
		case 1:
			host->addDockWidget(cycle % 2 ? Qt::LeftDockWidgetArea : Qt::RightDockWidgetArea, pluginDock);
			pluginDock->setFloating(false);
			if (cycle % 2 == 0)
				host->tabifyDockWidget(builtins.front(), pluginDock);
			pluginDock->show();
			pluginDock->raise();
			builtin = 0;
			phase = 2;
			break;
		case 2:
			if (builtins[builtin]->toggleViewAction()->isChecked())
				builtins[builtin]->toggleViewAction()->trigger();
			else
				builtins[builtin]->hide();
			phase = 3;
			break;
		case 3:
			if (!builtins[builtin]->isHidden() || builtins[builtin]->toggleViewAction()->isChecked()) {
				finish(false, "A built-in dock did not hide through its menu action");
				return;
			}
			builtins[builtin]->toggleViewAction()->trigger();
			phase = 4;
			break;
		case 4: {
			auto *dock = builtins[builtin];
			if (!dock->isVisible() || !dock->toggleViewAction()->isChecked()) {
				finish(false, "A built-in dock failed to become visible through its menu action: " + dock->objectName());
				return;
			}
			if (dock->visibleRegion().isEmpty()) {
				if (!host->tabifiedDockWidgets(dock).contains(pluginDock) || (!baseline && !baselineTabOcclusions)) {
					finish(false, "A built-in dock is unexpectedly occluded after its menu action: " + dock->objectName());
					return;
				}
				// Qt's toggleViewAction calls show(), which does not select an
				// inactive dock tab. Confirm the plain dock behaves the same,
				// then test tab selection separately from menu visibility.
				if (baseline)
					++baselineTabOcclusions;
				else
					++tabOcclusions;
			}
			dock->raise();
			phase = 5;
			break;
		}
		case 5: {
			auto *dock = builtins[builtin];
			if (dock->visibleRegion().isEmpty()) {
				finish(false, "A built-in dock remained occluded after selecting its tab: " + dock->objectName());
				return;
			}
			if (QWidget::mouseGrabber() || QWidget::keyboardGrabber()) {
				finish(false, "A dock operation left input captured");
				return;
			}
			// Check the native view tree as well as Qt's logical visibility.
			if (plugin) {
				auto *preview = plugin->findChild<OBSQTDisplay *>();
				NSView *previewView = (__bridge NSView *)reinterpret_cast<void *>(preview->winId());
				NSView *hostView = (__bridge NSView *)reinterpret_cast<void *>(host->winId());
				if ([previewView window] != [hostView window]) {
					finish(false, "The docked preview still belongs to a different native window");
					return;
				}
				const QPoint point = host->mapFromGlobal(dock->mapToGlobal(dock->rect().center()));
				const CGFloat y = [hostView isFlipped] ? point.y() : NSHeight([hostView bounds]) - point.y();
				NSView *hit = [hostView hitTest:NSMakePoint(point.x(), y)];
				if (hit && (hit == previewView || [hit isDescendantOf:previewView])) {
					finish(false, "The native preview covers a built-in dock: " + dock->objectName());
					return;
				}
			}
			if (baseline)
				++baselineChecks;
			else
				++checks;
			if (++builtin < builtins.size()) {
				phase = 2;
			} else if (++cycle < (baseline ? 2 : cycles)) {
				phase = 0;
			} else if (baseline) {
				host->removeDockWidget(pluginDock);
				pluginDock->deleteLater();
				pluginDock = nullptr;
				baseline = false;
				cycle = 0;
				phase = 0;
				createSourceDock();
				return;
			} else {
				finish(true, "Completed 200 float/dock cycles and all built-in dock menu checks");
				return;
			}
			break;
		}
		}
		QTimer::singleShot(20, this, [this]() { step(); });
	}

public:
	explicit MacDockStress(QMainWindow *window, QString path) : QObject(window), host(window), reportPath(path) {}
	void start()
	{
		elapsed.start();
		if (QGuiApplication::platformName() != "cocoa") {
			finish(false, "The test requires native Cocoa; offscreen testing is not sufficient");
			return;
		}
		for (const char *name : {"scenesDock", "sourcesDock", "mixerDock", "transitionsDock", "controlsDock"}) {
			if (auto *dock = host->findChild<QDockWidget *>(QString::fromUtf8(name)))
				builtins.push_back(dock);
		}
		if (builtins.size() != 5) {
			finish(false, "Could not locate all five actual OBS built-in docks");
			return;
		}
		sourceType = qEnvironmentVariable("SOURCE_DOCK_STRESS_SOURCE", "browser");
		pluginDock = new QDockWidget("Plain dock baseline", host);
		pluginDock->setObjectName("PlainDockBaseline");
		pluginDock->setWidget(new QWidget(pluginDock));
		host->addDockWidget(Qt::RightDockWidgetArea, pluginDock);
		host->showNormal();
		host->raise();
		QTimer::singleShot(1000, this, [this]() { step(); });
	}

private:
	void createSourceDock()
	{
		obs_data_t *settings = obs_data_create();
		obs_data_set_int(settings, "width", 640);
		obs_data_set_int(settings, "height", 360);
		obs_data_set_int(settings, "color", 0xff55aa33);
		if (sourceType == "browser") {
			obs_data_set_string(settings, "url", "data:text/html,%3Chtml%3E%3Cbody%20style='background:%232d7788'%3ESource%20Dock%20stress%3C/body%3E%3C/html%3E");
			obs_data_set_int(settings, "fps", 30);
		}
		obs_source_t *source = obs_source_create(sourceType == "browser" ? "browser_source" : "color_source_v3",
			"Dock stress source", settings, nullptr);
		obs_data_release(settings);
		if (!source) {
			finish(false, "Could not create the actual OBS test source: " + sourceType);
			return;
		}
		plugin = new SourceDock("SourceDockStress", false, host);
		plugin->SetSource(source);
		plugin->EnablePreview();
		obs_source_release(source);
		if (!obs_frontend_add_dock_by_id("SourceDockStress", "SourceDockStress", plugin)) {
			delete plugin;
			plugin = nullptr;
			finish(false, "OBS could not register the stress dock");
			return;
		}
		source_docks.push_back(plugin);
		pluginDock = qobject_cast<QDockWidget *>(plugin->parentWidget());
		if (!pluginDock) {
			finish(false, "OBS did not create a QDockWidget for Source Dock");
			return;
		}
		host->showNormal();
		host->raise();
		QTimer::singleShot(1000, this, [this]() { step(); });
	}
};

static void stressFrontendEvent(enum obs_frontend_event event, void *)
{
	if (event != OBS_FRONTEND_EVENT_FINISHED_LOADING)
		return;
	obs_frontend_remove_event_callback(stressFrontendEvent, nullptr);
	auto *window = static_cast<QMainWindow *>(obs_frontend_get_main_window());
	const QString path = qEnvironmentVariable("SOURCE_DOCK_STRESS_REPORT");
	if (window && !path.isEmpty()) {
		auto *test = new MacDockStress(window, path);
		QTimer::singleShot(3000, test, [test]() { test->start(); });
	}
}

MODULE_EXPORT void obs_module_post_load(void)
{
	if (!qEnvironmentVariableIsEmpty("SOURCE_DOCK_STRESS_REPORT"))
		obs_frontend_add_event_callback(stressFrontendEvent, nullptr);
}
