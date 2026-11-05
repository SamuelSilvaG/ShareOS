################################################################################
#
# shareos-syncthing – Syncthing (file synchronisation) for the system app
# "syncthing"
#
################################################################################

SHAREOS_SYNCTHING_VERSION = v2.1.7
SHAREOS_SYNCTHING_SITE = https://github.com/syncthing/syncthing.git
SHAREOS_SYNCTHING_SITE_METHOD = git
SHAREOS_SYNCTHING_LICENSE = MPL-2.0
SHAREOS_SYNCTHING_LICENSE_FILES = LICENSE
SHAREOS_SYNCTHING_GOMOD = github.com/syncthing/syncthing
# modules through the Go module proxy (see shareos-tailscale); no cgo: the
# database is the pure Go SQLite (modernc)
SHAREOS_SYNCTHING_GO_ENV = GOPROXY=https://proxy.golang.org,direct CGO_ENABLED=0
SHAREOS_SYNCTHING_BUILD_TARGETS = cmd/syncthing
# noupgrade: updates come from the store; noassets: without Syncthing's own web
# interface (ShareOS talks to its REST API, the app "Syncthing" is the interface)
SHAREOS_SYNCTHING_TAGS = noupgrade noassets
SHAREOS_SYNCTHING_LDFLAGS = -s -w \
	-X github.com/syncthing/syncthing/lib/build.Version=$(SHAREOS_SYNCTHING_VERSION) \
	-X github.com/syncthing/syncthing/lib/build.User=shareos \
	-X github.com/syncthing/syncthing/lib/build.Host=shareos \
	-X github.com/syncthing/syncthing/lib/build.Tags=noupgrade,noassets

$(eval $(golang-package))
