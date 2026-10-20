include $(sort $(wildcard $(BR2_EXTERNAL_SHAREOS_PATH)/package/*/*.mk))

# libwebsockets is only there for ttyd (System -> Terminal):
# - no HTTP/2: over HTTPS the browser would speak h2, which has no Host header,
#   and ttyd's origin check (-O) then refuses the terminal's WebSocket
# - no secure streams / connection monitor (and no HTML parser, which pulls
#   secure streams in): they ask
#   connectivitycheck.android.com in the background (captive portal check)
LIBWEBSOCKETS_CONF_OPTS += -DLWS_WITH_HTTP2=OFF -DLWS_WITH_SECURE_STREAMS=OFF -DLWS_WITH_CONMON=OFF \
	-DLWS_WITH_LHP=OFF
