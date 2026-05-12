.PHONY: help gen build test test-unit test-ui clean fmt
.DEFAULT_GOAL := help

PROJECT := BudgetBot.xcodeproj
SCHEME  := BudgetBot
# Override on the command line: `make test SIM='iPhone 16 Pro'`
SIM     ?= iPhone 17
DEST    := platform=iOS Simulator,name=$(SIM)

help:  ## Show this help
	@awk 'BEGIN{FS=":.*?## "}/^[a-zA-Z_-]+:.*?## /{printf "  \033[36m%-12s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)

gen:  ## Regenerate Xcode project from project.yml
	xcodegen generate

build: gen  ## Build the app for the simulator
	xcodebuild build \
	  -project $(PROJECT) -scheme $(SCHEME) \
	  -sdk iphonesimulator \
	  -destination 'generic/platform=iOS Simulator' \
	  CODE_SIGNING_ALLOWED=NO

test: gen  ## Run unit + UI tests
	xcodebuild test \
	  -project $(PROJECT) -scheme $(SCHEME) \
	  -sdk iphonesimulator \
	  -destination '$(DEST)' \
	  CODE_SIGNING_ALLOWED=NO

test-unit: gen  ## Run unit tests only (skips XCUITest)
	xcodebuild test \
	  -project $(PROJECT) -scheme $(SCHEME) \
	  -sdk iphonesimulator \
	  -destination '$(DEST)' \
	  -only-testing:BudgetBotTests \
	  CODE_SIGNING_ALLOWED=NO

test-ui: gen  ## Run XCUITest target only
	xcodebuild test \
	  -project $(PROJECT) -scheme $(SCHEME) \
	  -sdk iphonesimulator \
	  -destination '$(DEST)' \
	  -only-testing:BudgetBotUITests \
	  CODE_SIGNING_ALLOWED=NO

clean:  ## Remove generated project and DerivedData
	rm -rf $(PROJECT)
	rm -rf ~/Library/Developer/Xcode/DerivedData/BudgetBot-*
