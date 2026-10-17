#include <QApplication>
#include <QEnterEvent>
#include <QKeyEvent>
#include <QMouseEvent>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <vector>

#include "source-dock.hpp"

struct Move {
	obs_mouse_event event;
	bool leave;
};

static std::vector<Move> moves;
static int keyClicks = 0;
static const char *sourceName(void *) { return "Event regression source"; }
static void *createSource(obs_data_t *, obs_source_t *) { return &moves; }
static void destroySource(void *) {}
static uint32_t width(void *) { return 200; }
static uint32_t height(void *) { return 100; }
static void mouseMove(void *, const obs_mouse_event *event, bool leave) { moves.push_back({*event, leave}); }
static void keyClick(void *, const obs_key_event *, bool) { ++keyClicks; }

static void require(bool value, const char *message)
{
	if (!value) {
		std::cerr << "FAIL: " << message << '\n';
		std::exit(1);
	}
}

static void sendMove(SourceDock &dock, const QPointF &pos, Qt::MouseButtons buttons = Qt::NoButton,
		     Qt::KeyboardModifiers modifiers = Qt::NoModifier)
{
	QMouseEvent event(QEvent::MouseMove, pos, pos, pos, Qt::NoButton, buttons, modifiers);
	// Exercise the production filter directly for coordinates outside the
	// hidden test widget, which QApplication otherwise discards.
	require(dock.eventFilter->filter(dock.preview, &event), "move consumed by production filter");
}

int main(int argc, char **argv)
{
	QApplication app(argc, argv);
	require(obs_startup("en-US", nullptr, nullptr), "libobs startup");
	obs_source_info info{};
	info.id = "source_dock_event_regression";
	info.type = OBS_SOURCE_TYPE_INPUT;
	info.output_flags = OBS_SOURCE_VIDEO | OBS_SOURCE_INTERACTION | OBS_SOURCE_CUSTOM_DRAW;
	info.get_name = sourceName;
	info.create = createSource;
	info.destroy = destroySource;
	info.get_width = width;
	info.get_height = height;
	info.mouse_move = mouseMove;
	info.key_click = keyClick;
	obs_register_source(&info);
	obs_source_t *source = obs_source_create(info.id, "regression", nullptr, nullptr);
	require(source != nullptr, "create interactive libobs source");
	{
		SourceDock dock("regression", false);
		dock.source = source;
		dock.preview = new OBSQTDisplay(&dock);
		dock.preview->setFixedSize(200, 100);
		dock.preview->installEventFilter(dock.eventFilter.get());
		obs_source_inc_showing(source); // Balance the production destructor.

		if (argc > 1 && QString::fromUtf8(argv[1]) == "--enter-only") {
			QEnterEvent enter(QPointF(20, 30), QPointF(20, 30), QPointF(20, 30));
			QApplication::sendEvent(dock.preview, &enter);
			require(moves.size() == 1 && !moves.back().leave, "typed Enter event");
			std::cout << "PASS: Enter event\n";
			return 0;
		}

		// A real plain QEvent is the regression trigger. No QMouseEvent payload.
		QEvent leave(QEvent::Leave);
		moves.clear();
		QApplication::sendEvent(dock.preview, &leave);
		require(moves.size() == 1 && moves.back().leave, "plain Leave is forwarded safely");
		require(moves.back().event.x == 0 && moves.back().event.y == 0 && moves.back().event.modifiers == 0,
			"Leave uses initialized payload");
		std::cout << "PASS: plain Leave and initialized payload\n";

		QEnterEvent enter(QPointF(20, 30), QPointF(20, 30), QPointF(20, 30));
		moves.clear();
		QApplication::sendEvent(dock.preview, &enter);
		require(moves.size() == 1 && !moves.back().leave, "Enter is forwarded");
		require(moves.back().event.x == 20 && moves.back().event.y == 30, "Enter coordinates");
		std::cout << "PASS: typed Enter and coordinates\n";

		moves.clear();
		sendMove(dock, QPointF(40, 60), Qt::RightButton | Qt::MiddleButton,
			 Qt::ShiftModifier | Qt::ControlModifier | Qt::AltModifier);
		require(moves.size() == 1 && !moves.back().leave, "normal move is forwarded");
		require(moves.back().event.x == 40 && moves.back().event.y == 60, "move coordinates");
		require(moves.back().event.modifiers == (INTERACT_MOUSE_RIGHT | INTERACT_MOUSE_MIDDLE |
			INTERACT_SHIFT_KEY | INTERACT_CONTROL_KEY | INTERACT_ALT_KEY), "mouse and keyboard modifiers");
		std::cout << "PASS: normal move, coordinates and modifiers\n";

		moves.clear();
		sendMove(dock, QPointF(-10, 30));
		require(moves.size() == 1 && moves.back().leave, "outside source reports mouse leave");
		std::cout << "PASS: outside-source move\n";

		dock.scrollX = dock.scrollY = 0.5f;
		dock.scrollingFromX = dock.scrollingFromY = 10;
		moves.clear();
		sendMove(dock, QPointF(30, 20), Qt::LeftButton, Qt::ControlModifier);
		require(moves.empty(), "Ctrl-left pan is not sent to source");
		require(std::fabs(dock.scrollX - 0.4f) < 0.0001f && std::fabs(dock.scrollY - 0.4f) < 0.0001f,
			"Ctrl-left pan updates scroll");
		require(dock.scrollingFromX == 30 && dock.scrollingFromY == 20, "pan anchor updated");
		std::cout << "PASS: Ctrl-left pan\n";

		sendMove(dock, QPointF(1000, -1000), Qt::LeftButton, Qt::ControlModifier);
		require(dock.scrollX == 0.0f && dock.scrollY == 1.0f, "pan clamps scroll bounds");
		std::cout << "PASS: pan limits\n";

		const float beforeX = dock.scrollX, beforeY = dock.scrollY;
		moves.clear();
		QApplication::sendEvent(dock.preview, &leave);
		QApplication::sendEvent(dock.preview, &enter);
		require(moves.size() == 2 && moves[0].leave && !moves[1].leave, "Leave and Enter after pan");
		require(dock.scrollX == beforeX && dock.scrollY == beforeY, "boundary events do not pan");
		std::cout << "PASS: boundary events after pan\n";

		moves.clear();
		keyClicks = 0;
		QKeyEvent f1(QEvent::KeyPress, Qt::Key_F1, Qt::NoModifier);
		QApplication::sendEvent(dock.preview, &f1);
		require(keyClicks == 1 && moves.empty(), "F1 key stays on key event path");
		QApplication::sendEvent(dock.preview, &leave);
		require(moves.size() == 1 && moves.back().leave, "F1 followed by Leave");
		std::cout << "PASS: F1 key dispatch followed by Leave\n";

		QEvent help(QEvent::WhatsThis);
		require(!dock.eventFilter->filter(dock.preview, &help), "help event falls through");
#ifndef LEGACY_HANDLER
		require(!dock.HandleMouseMoveEvent(&help), "unrelated event rejected");
#endif
		require(!dock.HandleMouseMoveEvent(nullptr), "null event rejected");
		std::cout << "PASS: help and null guards\n";

		dock.source = nullptr;
		moves.clear();
		QApplication::sendEvent(dock.preview, &leave);
		QApplication::sendEvent(dock.preview, &enter);
		sendMove(dock, QPointF(5, 5));
		require(moves.empty(), "no source produces no OBS interaction");
		std::cout << "PASS: no-source boundary and move events\n";
		dock.source = source;

		moves.clear();
		for (int i = 0; i < 1000; ++i) {
			QApplication::sendEvent(dock.preview, &leave);
			QApplication::sendEvent(dock.preview, &enter);
		}
		require(moves.size() == 2000, "repeated boundary events");
		std::cout << "PASS: 1,000 Leave/Enter cycles\n";
	}
	obs_source_release(source);
	obs_shutdown();
	std::cout << "All 11 regression groups passed.\n";
}
