help:
	@echo "hello"

local:
	-$(MAKE) -C ./application $(@)

emulators:
	-$(MAKE) -C ./landing_page $(@)
