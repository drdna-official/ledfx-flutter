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
			fastforge release --skip-clean --name production $(OUT_FLAG) --jobs $(subst $(space),$(comma),$(SELECTED_JOBS)) && \
			$(if $(filter android,$(SELECTED_JOBS)), \
				echo "--------------------------------------------------------" && \
				echo "  Post-processing Android: Collecting split APKs..." && \
				$(if $(filter Windows_NT,$(OS)), \
					powershell -NoProfile -Command " \
						$$v = (Get-Content pubspec.yaml | Select-String 'version:').ToString().Split(':')[1].Trim(); \
						$$d = '$(OUT_PATH)'; if (!$$d) { $$d = 'dist' }; \
						$$targetDir = \"$$d/$$v\"; \
						if (Test-Path 'build/app/outputs/flutter-apk/app-arm64-v8a-release.apk') { \
							if (!(Test-Path \"$$targetDir\")) { New-Item -ItemType Directory -Path \"$$targetDir\" -Force | Out-Null }; \
							Copy-Item 'build/app/outputs/flutter-apk/app-arm64-v8a-release.apk' -Destination \"$$targetDir/ledfx-$$v-android-arm64.apk\" -Force; \
							Write-Host '  + Collected: ledfx-$$v-android-arm64.apk'; \
						}; \
						if (Test-Path 'build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk') { \
							if (!(Test-Path \"$$targetDir\")) { New-Item -ItemType Directory -Path \"$$targetDir\" -Force | Out-Null }; \
							Copy-Item 'build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk' -Destination \"$$targetDir/ledfx-$$v-android-armv7.apk\" -Force; \
							Write-Host '  + Collected: ledfx-$$v-android-armv7.apk'; \
						}; \
						if (Test-Path \"$$targetDir/ledfx-$$v-android.apk\") { \
							Remove-Item \"$$targetDir/ledfx-$$v-android.apk\" -ErrorAction SilentlyContinue; \
						}; \
					", \
					VERSION=$$(grep "^version:" pubspec.yaml | cut -d " " -f 2) && \
					OUT=$$(if [ -n "$(OUT_PATH)" ]; then echo "$(OUT_PATH)"; else echo "dist"; fi) && \
					TDIR="$$OUT/$$VERSION" && \
					if [ -f "build/app/outputs/flutter-apk/app-arm64-v8a-release.apk" ]; then \
						cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk $$TDIR/ledfx-$$VERSION-android-arm64.apk && \
						echo "  + Collected: ledfx-$$VERSION-android-arm64.apk"; \
					fi && \
					if [ -f "build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk" ]; then \
						cp build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk $$TDIR/ledfx-$$VERSION-android-armv7.apk && \
						echo "  + Collected: ledfx-$$VERSION-android-armv7.apk"; \
					fi && \
					rm -f $$TDIR/ledfx-$$VERSION-android.apk \
				) \
			) \
		), \
		echo "Built $@ already..." \
	)

# Dummy targets to support flags and paths as positional arguments
-o:
	@:

# Catch-all to silence unknown positional arguments (like the output path)
%:
	@:
