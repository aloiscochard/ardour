#!/bin/bash
# this script creates a windows32 version of ardour3
# cross-compiled on GNU/Linux
#
# It is intended to run in a pristine chroot or VM of a minimal
# debian system. see http://wiki.debian.org/cowbuilder
#
### Quick start: (host, setup cowbuilder)
#
# sudo apt-get install cowbuilder util-linux
# sudo mkdir -p /var/cache/pbuilder/jessie-i386/
#
# sudo i386 cowbuilder --create \
#     --basepath /var/cache/pbuilder/jessie-i386/base.cow \
#     --distribution jessie \
#     --debootstrapopts --arch --debootstrapopts i386
#
# sudo i386 cowbuilder --login --bindmounts /tmp \
#     --basepath /var/cache/pbuilder/jessie-i386/base.cow
#
### inside cowbuilder (/tmp/ is shared wit host)
# /tmp/this_script.sh
#
###############################################################################

: ${SRC=/usr/src}
: ${SRCDIR=/tmp/winsrc}
: ${PREFIX=$SRC/win-stack}
: ${BUILDD=$SRC/win-build}
: ${MAKEFLAGS=-j4}

if [ "$(id -u)" != "0" -a -z "$SUDO" ]; then
	echo "This script must be run as root in pbuilder" 1>&2
  echo "e.g sudo DIST=jessie ARCH=i386 linux32 cowbuilder --bindmounts /tmp --execute $0"
	exit 1
fi

set -e

apt-get -y install build-essential \
	gcc-mingw-w64-i686 g++-mingw-w64-i686 mingw-w64-tools mingw32 \
	wget git autoconf automake libtool pkg-config \
	curl unzip ed yasm cmake zip

cd "$SRC"

###############################################################################

mkdir -p ${SRCDIR}
mkdir -p ${PREFIX}
mkdir -p ${BUILDD}

unset PKG_CONFIG_PATH
export PKG_CONFIG_PATH=${PREFIX}/lib/pkgconfig
export PREFIX
export SRCDIR

function download {
echo "--- Downloading.. $2"
test -f ${SRCDIR}/$1 || curl -k -L -o ${SRCDIR}/$1 $2
}

function src {
download ${1}.${2} $3
cd ${BUILDD}
tar xf ${SRCDIR}/${1}.${2}
cd $1
}

function autoconfbuild {
set -e
echo "======= $(pwd) ======="
PATH=${PREFIX}/bin:/usr/bin:/bin:/usr/sbin:/sbin \
	CPPFLAGS="-I${PREFIX}/include$CPPFLAGS" \
	CFLAGS="-I${PREFIX}/include -O2$CFLAGS" \
	CXXFLAGS="-I${PREFIX}/include -O2$CXXFLAGS" \
	LDFLAGS="-L${PREFIX}/lib$LDFLAGS" \
	./configure --host=i686-w64-mingw32 --build=i386-linux \
	--prefix=$PREFIX $@
  make $MAKEFLAGS && make install
}

function wafbuild {
set -e
echo "======= $(pwd) ======="
PATH=${PREFIX}/bin:/usr/bin:/bin:/usr/sbin:/sbin \
	CC=i686-w64-mingw32-gcc \
	CXX=i686-w64-mingw32-c++ \
	CPP=i686-w64-mingw32-cpp \
	AR=i686-w64-mingw32-ar \
	LD=i686-w64-mingw32-ld \
	NM=i686-w64-mingw32-nm \
	AS=i686-w64-mingw32-as \
	STRIP=i686-w64-mingw32-strip \
	RANLIB=i686-w64-mingw32-ranlib \
	DLLTOOL=i686-w64-mingw32-dlltool \
	./waf configure --prefix=$PREFIX $@ \
	&& ./waf && ./waf install
}

################################################################################
if test -z "$NOSTACK"; then
################################################################################

download jack_win32.tar.xz http://robin.linuxaudio.org/jack_win32.tar.xz
cd "$PREFIX"
tar xf ${SRCDIR}/jack_win32.tar.xz
"$PREFIX"/update_pc_prefix.sh

download pthreads-w32-2-9-1-release.tar.gz ftp://sourceware.org/pub/pthreads-win32/pthreads-w32-2-9-1-release.tar.gz
cd ${BUILDD}
tar xzf ${SRCDIR}/pthreads-w32-2-9-1-release.tar.gz
cd pthreads-w32-2-9-1-release
make clean GC CROSS=i686-w64-mingw32-
mkdir -p ${PREFIX}/bin
mkdir -p ${PREFIX}/lib
mkdir -p ${PREFIX}/include
cp -vf pthreadGC2.dll ${PREFIX}/bin/
cp -vf libpthreadGC2.a ${PREFIX}/lib/libpthread.a
cp -vf pthread.h sched.h ${PREFIX}/include

src zlib-1.2.7 tar.gz ftp://ftp.simplesystems.org/pub/libpng/png/src/history/zlib/zlib-1.2.7.tar.gz
make -fwin32/Makefile.gcc PREFIX=i686-w64-mingw32-
make install -fwin32/Makefile.gcc SHARED_MODE=1 \
	INCLUDE_PATH=${PREFIX}/include \
	LIBRARY_PATH=${PREFIX}/lib \
	BINARY_PATH=${PREFIX}/bin

src tiff-4.0.1 tar.gz ftp://ftp.remotesensing.org/pub/libtiff/tiff-4.0.1.tar.gz
autoconfbuild

download jpegsrc.v9a.tar.gz http://www.ijg.org/files/jpegsrc.v9a.tar.gz
cd ${BUILDD}
tar xzf ${SRCDIR}/jpegsrc.v9a.tar.gz
cd jpeg-9a
autoconfbuild

src libogg-1.3.2 tar.gz http://downloads.xiph.org/releases/ogg/libogg-1.3.2.tar.gz
autoconfbuild

src libvorbis-1.3.4 tar.gz http://downloads.xiph.org/releases/vorbis/libvorbis-1.3.4.tar.gz
autoconfbuild --disable-examples --with-ogg=${PREFIX}

src flac-1.2.1 tar.gz http://downloads.xiph.org/releases/flac/flac-1.2.1.tar.gz
ed Makefile.in << EOF
%s/examples / /
wq
EOF
autoconfbuild
# add -lwsock32 to /usr/src/win-stack/lib/pkgconfig/flac.pc ??

src libsndfile-1.0.25 tar.gz http://www.mega-nerd.com/libsndfile/files/libsndfile-1.0.25.tar.gz
ed Makefile.in << EOF
%s/ examples regtest tests programs//
wq
EOF
LDFLAGS=" -lFLAC -lwsock32 -lvorbis -logg -lwsock32" \
autoconfbuild
ed $PREFIX/lib/pkgconfig/sndfile.pc << EOF
%s/ -lsndfile/ -lsndfile -lvorbis -lvorbisenc -lFLAC -logg -lwsock32/
wq
EOF

src libsamplerate-0.1.8 tar.gz http://www.mega-nerd.com/SRC/libsamplerate-0.1.8.tar.gz
ed Makefile.in << EOF
%s/ examples tests//
wq
EOF
autoconfbuild

src expat-2.1.0 tar.gz http://prdownloads.sourceforge.net/expat/expat-2.1.0.tar.gz
autoconfbuild

src libiconv-1.14 tar.gz ftp://ftp.gnu.org/gnu/libiconv/libiconv-1.14.tar.gz
autoconfbuild --with-included-gettext --with-libiconv-prefix=$PREFIX

src libxml2-2.7.8 tar.gz ftp://xmlsoft.org/libxslt/libxml2-2.7.8.tar.gz
autoconfbuild --with-threads=no

src freetype-2.5.3 tar.gz http://download.savannah.gnu.org/releases/freetype/freetype-2.5.3.tar.gz
autoconfbuild -with-harfbuzz=no --with-png=no

#src harfbuzz-0.9.22 tar.bz2 http://www.freedesktop.org/software/harfbuzz/release/harfbuzz-0.9.22.tar.bz2
#autoconfbuild

src fontconfig-2.11.0 tar.bz2 http://www.freedesktop.org/software/fontconfig/release/fontconfig-2.11.0.tar.bz2
ed Makefile.in << EOF
%s/conf.d test /conf.d /
wq
EOF
autoconfbuild

#src libpng-1.6.12 tar.gz ftp://ftp.simplesystems.org/pub/libpng/png/src/libpng16/libpng-1.6.12.tar.gz
src libpng-1.6.12 tar.gz https://downloads.sourceforge.net/project/libpng/libpng16/1.6.12/libpng-1.6.12.tar.gz
autoconfbuild

src pixman-0.30.2 tar.gz http://cgit.freedesktop.org/pixman/snapshot/pixman-0.30.2.tar.gz
./autogen.sh
autoconfbuild

src cairo-1.12.16 tar.xz http://cairographics.org/releases/cairo-1.12.16.tar.xz
autoconfbuild

src libffi-3.0.10 tar.gz ftp://sourceware.org/pub/libffi/libffi-3.0.10.tar.gz
autoconfbuild

src gettext-0.18.2 tar.gz http://ftp.gnu.org/pub/gnu/gettext/gettext-0.18.2.tar.gz
autoconfbuild

################################################################################
apt-get -y install python gettext libglib2.0-dev # /usr/bin/msgfmt , genmarshall
################################################################################

src glib-2.42.0 tar.xz  http://ftp.gnome.org/pub/gnome/sources/glib/2.42/glib-2.42.0.tar.xz
LIBS="-lpthread" \
autoconfbuild --with-pcre=internal --disable-silent-rules --with-libiconv=no

################################################################################
dpkg -P gettext python || true
export PATH=$PREFIX/bin:$PATH
rm -f ${PREFIX}/lib/pkgconfig/harfbuzz.pc  || true
################################################################################

src pango-1.36.8 tar.xz http://ftp.gnome.org/pub/GNOME/sources/pango/1.36/pango-1.36.8.tar.xz
autoconfbuild --without-x --with-included-modules=yes

src atk-2.2.0 tar.bz2 http://ftp.gnome.org/pub/GNOME/sources/atk/2.2/atk-2.2.0.tar.bz2
autoconfbuild --disable-rebuilds

src gdk-pixbuf-2.25.2 tar.xz http://ftp.gnome.org/pub/GNOME/sources/gdk-pixbuf/2.25/gdk-pixbuf-2.25.2.tar.xz
autoconfbuild --disable-modules --without-gdiplus --with-included-loaders=yes

src gtk+-2.24.24 tar.xz http://ftp.gnome.org/pub/gnome/sources/gtk+/2.24/gtk+-2.24.24.tar.xz
ed Makefile.in << EOF
%s/demos / /
wq
EOF
autoconfbuild --disable-modules --disable-rebuilds


#http://ardour.org/files/gtk-engines-2.21.0.tar.gz
#http://ftp.gnome.org/pub/GNOME/sources/gtk-engines/2.20/gtk-engines-2.20.2.tar.bz2

################################################################################
dpkg -P libglib2.0-dev libpcre3-dev || true
################################################################################

src lv2-1.10.0 tar.bz2 http://lv2plug.in/spec/lv2-1.10.0.tar.bz2
wafbuild --no-plugins

src serd-0.20.0 tar.bz2 http://download.drobilla.net/serd-0.20.0.tar.bz2
wafbuild

src sord-0.12.2 tar.bz2 http://download.drobilla.net/sord-0.12.2.tar.bz2
ed wscript << EOF
%s/pthread/lpthread/
wq
EOF
wafbuild

src sratom-0.4.6 tar.bz2 http://download.drobilla.net/sratom-0.4.6.tar.bz2
wafbuild

src lilv-0.20.0 tar.bz2 http://download.drobilla.net/lilv-0.20.0.tar.bz2
ed wscript << EOF
%s/'dl'//
%s/win32/linux/
wq
EOF
wafbuild
ed $PREFIX/lib/pkgconfig/lilv-0.pc << EOF
%s/-ldl//
wq
EOF

src suil-0.8.2 tar.bz2 http://download.drobilla.net/suil-0.8.2.tar.bz2
wafbuild

src curl-7.35.0 tar.bz2 http://curl.haxx.se/download/curl-7.35.0.tar.bz2
autoconfbuild

src libsigc++-2.4.0 tar.xz http://ftp.gnome.org/pub/GNOME/sources/libsigc++/2.4/libsigc++-2.4.0.tar.xz
autoconfbuild

src glibmm-2.32.0 tar.xz http://ftp.gnome.org/pub/GNOME/sources/glibmm/2.32/glibmm-2.32.0.tar.xz
autoconfbuild

src cairomm-1.10.0 tar.gz http://cairographics.org/releases/cairomm-1.10.0.tar.gz
autoconfbuild

src pangomm-2.28.4 tar.xz http://ftp.acc.umu.se/pub/gnome/sources/pangomm/2.28/pangomm-2.28.4.tar.xz
autoconfbuild

src atkmm-2.22.6 tar.xz http://ftp.gnome.org/pub/GNOME/sources/atkmm/2.22/atkmm-2.22.6.tar.xz
autoconfbuild

src gtkmm-2.24.4 tar.xz http://ftp.acc.umu.se/pub/GNOME/sources/gtkmm/2.24/gtkmm-2.24.4.tar.xz
autoconfbuild

src fftw-3.3.4 tar.gz http://www.fftw.org/fftw-3.3.4.tar.gz
autoconfbuild --enable-single --enable-float --enable-type-prefix --enable-sse --with-our-malloc --enable-avx --disable-mpi
make clean
autoconfbuild --enable-type-prefix --with-our-malloc --enable-avx --disable-mpi

################################################################################
src taglib-1.9.1 tar.gz http://taglib.github.io/releases/taglib-1.9.1.tar.gz
ed CMakeLists.txt << EOF
0i
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_C_COMPILER i686-w64-mingw32-gcc)
set(CMAKE_CXX_COMPILER i686-w64-mingw32-c++)
set(CMAKE_RC_COMPILER i686-w64-mingw32-windres)
.
wq
EOF
mkdir build && cd build
	cmake \
		-DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_RELEASE_TYPE=Release \
		-DCMAKE_SYSTEM_NAME=Windows -DZLIB_ROOT=$PREFIX \
		..
make $MAKEFLAGS && make install

# windows target does not create .pc file...
cat > $PREFIX/lib/pkgconfig/taglib.pc << EOF
prefix=$PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: TagLib
Description: Audio meta-data library
Requires:
Version: 1.9.1
Libs: -L\${libdir}/lib -ltag
Cflags: -I\${includedir}/include/taglib
EOF

################################################################################
#git://liblo.git.sourceforge.net/gitroot/liblo/liblo
src liblo-0.28 tar.gz http://downloads.sourceforge.net/liblo/liblo-0.28.tar.gz
PATH=${PREFIX}/bin:/usr/bin:/bin:/usr/sbin:/sbin \
	CPPFLAGS="-I${PREFIX}/include" \
	CFLAGS="-I${PREFIX}/include" \
	CXXFLAGS="-I${PREFIX}/include" \
	LDFLAGS="-L${PREFIX}/lib" \
	./configure --host=i686-w64-mingw32 --build=i386-linux --prefix=$PREFIX --enable-shared $@
ed src/Makefile << EOF
/noinst_PROGRAMS
.,+3d
wq
EOF
ed Makefile << EOF
%s/examples//
wq
EOF
make $MAKEFLAGS && make install

################################################################################
src boost_1_49_0 tar.bz2 http://sourceforge.net/projects/boost/files/boost/1.49.0/boost_1_49_0.tar.bz2
./bootstrap.sh --prefix=$PREFIX
echo "using gcc : 4.7 : i686-w64-mingw32-g++ :
<rc>i686-w64-mingw32-windres
<archiver>i686-w64-mingw32-ar
;" > user-config.jam
#	PTW32_INCLUDE=${PREFIX}/include \
#	PTW32_LIB=${PREFIX}/lib  \
	./b2 --prefix=$PREFIX \
	toolset=gcc \
	target-os=windows \
	variant=release \
	threading=multi \
	threadapi=win32 \
	link=shared \
	runtime-link=shared \
	--with-exception \
	--with-regex \
	--layout=tagged \
	--user-config=user-config.jam \
  -j 4 install

################################################################################
download ladspa.h http://www.ladspa.org/ladspa_sdk/ladspa.h.txt
cp ${SRCDIR}/ladspa.h $PREFIX/include/ladspa.h
################################################################################

src vamp-plugin-sdk-2.5 tar.gz http://code.soundsoftware.ac.uk/attachments/download/690/vamp-plugin-sdk-2.5.tar.gz
ed Makefile.in << EOF
%s/= ar/= i686-w64-mingw32-ar/
%s/= ranlib/= i686-w64-mingw32-ranlib/
wq
EOF
MAKEFLAGS="sdk -j4" autoconfbuild
ed $PREFIX/lib/pkgconfig/vamp-hostsdk.pc << EOF
%s/-ldl//
wq
EOF

src rubberband-1.8.1 tar.bz2 http://code.breakfastquay.com/attachments/download/34/rubberband-1.8.1.tar.bz2
ed Makefile.in << EOF
%s/= ar/= i686-w64-mingw32-ar/
wq
EOF
autoconfbuild
ed $PREFIX/lib/pkgconfig/rubberband.pc << EOF
%s/ -lrubberband/ -lrubberband -lfftw3/
wq
EOF

src mingw-libgnurx-2.5.1 tar.gz http://sourceforge.net/projects/mingw/files/Other/UserContributed/regex/mingw-regex-2.5.1/mingw-libgnurx-2.5.1-src.tar.gz/download
autoconfbuild

src aubio-0.3.2 tar.gz http://aubio.org/pub/aubio-0.3.2 tar.gz
ed Makefile.in << EOF
%s/examples / /
wq
EOF
autoconfbuild
ed $PREFIX/lib/pkgconfig/aubio.pc << EOF
%s/ -laubio/ -laubio -lfftw3f/
wq
EOF

src portaudio tgz http://portaudio.com/archives/pa_stable_v19_20140130.tgz
autoconfbuild

################################################################################
fi  # $NOSTACK
################################################################################
################################################################################


cd ${SRC}
ARDOURSRC=ardour-w32
git clone -b cairocanvas git://git.ardour.org/ardour/ardour.git $ARDOURSRC || true
cd ${ARDOURSRC}

export CC=i686-w64-mingw32-gcc
export CXX=i686-w64-mingw32-c++
export CPP=i686-w64-mingw32-cpp
export AR=i686-w64-mingw32-ar
export LD=i686-w64-mingw32-ld
export NM=i686-w64-mingw32-nm
export AS=i686-w64-mingw32-as
export STRIP=i686-w64-mingw32-strip
export RANLIB=i686-w64-mingw32-ranlib
export DLLTOOL=i686-w64-mingw32-dlltool

LDFLAGS="-L${PREFIX}/lib" ./waf configure \
	--dist-target=mingw --windows-vst \
	--also-include=${PREFIX}/include \
	--with-dummy \
	--prefix=${PREFIX}
./waf
./waf install

################################################################################
################################################################################
################################################################################

# somewhat whacky solution to zip it all up..
# TODO: NSIS to the rescue

DESTDIR=/tmp/a3win
ALIBDIR=$DESTDIR/lib/ardour3

echo " === DEPLOY to $DESTDIR"

rm -rf $DESTDIR
mkdir -p $DESTDIR/bin
mkdir -p $DESTDIR/share/
mkdir -p $ALIBDIR/surfaces
mkdir -p $ALIBDIR/backends
mkdir -p $ALIBDIR/lv2
mkdir -p $ALIBDIR/panners
mkdir -p $ALIBDIR/fst

cp build/libs/gtkmm2ext/gtkmm2ext-0.dll $DESTDIR/bin/
cp build/libs/midi++2/midipp-4.dll $DESTDIR/bin/
cp build/libs/evoral/evoral-0.dll $DESTDIR/bin/
cp build/libs/ardour/ardour-3.dll $DESTDIR/bin/
cp build/libs/timecode/timecode.dll $DESTDIR/bin/
cp build/libs/qm-dsp/qmdsp-0.dll $DESTDIR/bin/
cp build/libs/canvas/canvas-0.dll $DESTDIR/bin/
cp build/libs/pbd/pbd-4.dll $DESTDIR/bin/
cp build/libs/audiographer/audiographer-0.dll $DESTDIR/bin/
cp build/libs/fst/ardour-vst-scanner.exe $ALIBDIR/fst/
cp build/gtk2_ardour/ardour-*.exe $DESTDIR/bin/ardour.exe
cp build/libs/clearlooks-newer/clearlooks.dll $DESTDIR/bin/

cp $PREFIX/bin/*dll $DESTDIR/bin/
cp $PREFIX/lib/*dll $DESTDIR/bin/
rm -rf $DESTDIR/bin/libjack.dll

cp `find build/libs/surfaces/ -iname "*.dll"` $ALIBDIR/surfaces/
cp `find build/libs/backends/ -iname "*.dll"` $ALIBDIR/backends/
cp `find build/libs/panners/ -iname "*.dll"` $ALIBDIR/panners/
cp -r build/libs/LV2/* $DESTDIR/lib/lv2/

mv $ALIBDIR/surfaces/ardourcp-4.dll $DESTDIR/bin/

# TODO use -static-libgcc -static-libstdc++
cp /usr/lib/gcc/i686-w64-mingw32/4.6/libgcc_s_sjlj-1.dll /$DESTDIR/bin/
cp /usr/lib/gcc/i686-w64-mingw32/4.6/libstdc++-6.dll /$DESTDIR/bin/

cp -r $PREFIX/share/ardour3 $DESTDIR/share/
cp -r $PREFIX/etc/ardour3/* $DESTDIR/share/ardour3/

# parser errors: "DOCTYPE improperly terminated" - probably '\r\n' ??
rm -rf $DESTDIR/share/ardour3/patchfiles
rm -rf $DESTDIR/share/ardour3/midi_maps

du -sch $DESTDIR

################################################################################
cd /tmp/ ; rm -rf a3win.zip ; zip -r a3win.zip a3win/
ls -l a3win.zip