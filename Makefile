.PHONY: all check-fastforge android ios linux windows -o

all: check-fastforge
	fastforge release --name production $(OUT_FLAG)

# Helpers for string manipulation
null  :=
space := $(null) $(null)
comma := ,

# Detect OS and set appropriate path separator, Pub bin directory, and NULL device
ifeq ($(OS),Windows_NT)
	PATH_SEP := ;
	PUB_BIN := $(LOCALAPPDATA)/Pub/Cache/bin
	NULL := nul
else
	PATH_SEP := :
	PUB_BIN := $(HOME)/.pub-cache/bin
	NULL := /dev/null
endif

# Ensure global dart binaries and flutter are in the path
export PATH := $(PATH)$(PATH_SEP)$(PUB_BIN)

check-fastforge:
	@fastforge --version > $(NULL) 2>&1 || (echo "Fastforge not found. Installing..." && dart pub global activate fastforge)

# Extraction of jobs and optional output directory
PLATFORMS := android ios linux windows
SELECTED_JOBS := $(filter $(PLATFORMS),$(MAKECMDGOALS))

# Handle optional -o flag and manual tilde (~) expansion for Windows CMD
HOME_DIR := $(if $(filter Windows_NT,$(OS)),$(USERPROFILE),$(HOME))
EXTRA_ARGS := $(filter-out $(PLATFORMS) all check-fastforge execute -o,$(MAKECMDGOALS))
RAW_OUT_PATH := $(if $(filter -o,$(MAKECMDGOALS)),$(firstword $(EXTRA_ARGS)))
OUT_PATH := $(patsubst ~%,$(HOME_DIR)%,$(RAW_OUT_PATH))
OUT_FLAG := $(if $(OUT_PATH),--output "$(OUT_PATH)")

# Consolidates all command-line targets into a single comma-separated --jobs list
# The guard ensures it only runs once even if multiple platforms are specified
# The platform targets use a guard to ensure the build runs exactly once even if multiple platforms are specified
android ios linux windows: check-fastforge
	@$(if $(filter $@,$(firstword $(filter $(PLATFORMS),$(MAKECMDGOALS)))), \
		$(if $(SELECTED_JOBS), \
			echo "--------------------------------------------------------" && \
			echo "  Packaging System: [$(SELECTED_JOBS)]" && \
			$(if $(OUT_PATH),echo "  Output Directory: [$(OUT_PATH)]" &&) \
			echo "--------------------------------------------------------" && \
			fastforge release --skip-clean --name production $(OUT_FLAG) --jobs $(subst $(space),$(comma),$(SELECTED_JOBS)), \
			echo "Usage: make <platform1> <platform2> ... [-o output_path]" \
		) \
	)

# Dummy targets to support flags and paths as positional arguments
-o:
	@:

# Catch-all to silence unknown positional arguments (like the output path)
%:
	@:
