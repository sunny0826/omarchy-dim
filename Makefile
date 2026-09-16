QMLLINT := /usr/lib/qt6/bin/qmllint
# qmllint only resolves `qs.Commons` and `qs.Ui` when the shell's QML root is
# reachable as the `qs` module: the shell imports them as qs.*, so the import
# root has to be a directory that contains `qs`.
# Kept outside the plugin folder: omarchy plugin validate rejects symlinks inside it.
QML_IMPORT_ROOT := $(shell mktemp -d -t omarchy-dim-qml-XXXXXX)
QML_FILES := Panel.qml PanelContent.qml Usage.qml

.PHONY: test test-js test-python qml-check assets render probe preview validate

test: test-js test-python

# Model.js is plain JavaScript on purpose: the wording, units, and arithmetic
# are covered without a compositor.
test-js:
	node tests/test_model.js

test-python:
	python3 tests/test_dim_usage.py

# Every QML tool here needs the import root; making it a file target keeps the
# dependency in one place.
$(QML_IMPORT_ROOT)/qs:
	@mkdir -p $(QML_IMPORT_ROOT)
	@ln -sfn /usr/share/omarchy/shell $(QML_IMPORT_ROOT)/qs

qml-check: $(QML_IMPORT_ROOT)/qs
	$(QMLLINT) -I $(QML_IMPORT_ROOT) $(QML_FILES)

# The logo assets are derived, so they can always be rebuilt from the source
# of truth. Needs the network the first time.
assets:
	./scripts/build-mark-assets

# Draws the real QML — the bar button in each logo mode, and the panel body —
# into ~/.cache/guo-dim-check, using a throwaway quickshell instance and live
# data. Needs a running Wayland session. The window it opens is the render.
RENDER_DIR := $(HOME)/.cache/guo-dim-check
render: $(QML_IMPORT_ROOT)/qs
	mkdir -p $(RENDER_DIR)
	HARNESS_PLUGIN_DIR=$(CURDIR) HARNESS_OUT=$(RENDER_DIR)/bar- \
		QML_IMPORT_PATH=$(QML_IMPORT_ROOT) quickshell -p tests/render/grab.qml
	HARNESS_PLUGIN_DIR=$(CURDIR) HARNESS_OUT=$(RENDER_DIR)/panel.png \
		QML_IMPORT_PATH=$(QML_IMPORT_ROOT) quickshell -p tests/render/grab-panel.qml
	@echo "renders in $(RENDER_DIR)"

# The listing preview: renders the bar button and the panel body, then composes
# them into preview.png at the plugin root. Both steps are deterministic.
preview: $(QML_IMPORT_ROOT)/qs
	mkdir -p $(RENDER_DIR)
	HARNESS_PLUGIN_DIR=$(CURDIR) HARNESS_OUT=$(RENDER_DIR)/bar- \
		QML_IMPORT_PATH=$(QML_IMPORT_ROOT) quickshell -p tests/render/grab.qml
	HARNESS_PLUGIN_DIR=$(CURDIR) HARNESS_OUT=$(RENDER_DIR)/panel.png \
		QML_IMPORT_PATH=$(QML_IMPORT_ROOT) quickshell -p tests/render/grab-panel.qml
	./scripts/build-preview
	@echo "wrote preview.png"

# Prints what the widget derives from a live snapshot, without drawing: the
# cheapest way to see whether the data path is intact.
probe: $(QML_IMPORT_ROOT)/qs
	HARNESS_PLUGIN_DIR=$(CURDIR) \
		QML_IMPORT_PATH=$(QML_IMPORT_ROOT) quickshell -p tests/render/shell.qml

validate: test qml-check
	omarchy plugin validate .
