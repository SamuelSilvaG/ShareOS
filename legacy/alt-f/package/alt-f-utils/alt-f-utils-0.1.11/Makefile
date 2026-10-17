
# rpcinfo now supplied by rpcbind

ifneq ($(STRIP),true)
	BINS = sysctrl dns323-fw dns320l-daemon
	# unbuffer.so
else
	BINS = dns323-fw
endif

all: $(BINS)

clean:
	$(RM) $(BINS) *.o

install install-strip: $(BINS)
	$(STRIP) $(BINS)
	mkdir -p $(DESTDIR)/usr/sbin
	cp -a $(BINS) $(DESTDIR)/usr/sbin/

uninstall:
	-cd $(DESTDIR)/usr/sbin && rm -f $(BINS)

unbuffer.so: unbuffer.c
	$(CC) unbuffer.c -fPIC -shared -o $@
