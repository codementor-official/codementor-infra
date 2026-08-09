SHELL := /bin/bash

# Each subfolder owns its own Makefile. This one only dispatches to them.
SUBDIRS   := $(patsubst %/Makefile,%,$(wildcard */Makefile))
BROADCAST := up down init seed verify reset

.PHONY: help $(BROADCAST)

help:
	@echo "make <target>              run target in every subfolder that defines it"
	@echo "make <subfolder>           show that subfolder's own help"
	@echo "make <subfolder>/<target>  run one target in one subfolder (e.g. make database/psql)"
	@echo ""
	@echo "subfolders:          $(SUBDIRS)"
	@echo "broadcast targets:   $(BROADCAST)"

$(BROADCAST):
	@for d in $(SUBDIRS); do \
	  if $(MAKE) -C $$d -n $@ >/dev/null 2>&1; then \
	    echo "==> $$d: $@"; \
	    $(MAKE) -C $$d $@ || exit $$?; \
	  fi; \
	done

# ponytail: eval-generated per-subfolder rules; plain pattern rules can't match "<dir>/<target>"
define SUBDIR_RULES
.PHONY: $(1) $(1)/%
$(1):
	@$$(MAKE) -C $(1) help
$(1)/%:
	@$$(MAKE) -C $(1) $$*
endef
$(foreach d,$(SUBDIRS),$(eval $(call SUBDIR_RULES,$(d))))
