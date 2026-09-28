# Maintainer: Klickmeister contributors
pkgname=klickmeister
pkgver=0.1.2
pkgrel=2
pkgdesc='Small, safe auto clicker for KDE Plasma Wayland'
arch=('x86_64')
url='https://github.com/jerry0205/Auto-Clicker'
license=('MIT')
depends=('gcc-libs' 'glibc' 'kirigami' 'qt6-base' 'qt6-declarative' 'xdg-desktop-portal' 'xdg-desktop-portal-kde')
makedepends=('cargo' 'clang' 'lld' 'pkgconf' 'qt6-tools' 'rust')
options=('!lto')
# No release tag exists for 0.1.2; pin the published 0.1.2 source tree.
_commit=4b9d1d711889ddfbfc9f92e5a363cd35aabbf10f
source=("Auto-Clicker-${_commit}.tar.gz::https://github.com/Jerry0205/Auto-Clicker/archive/${_commit}.tar.gz")
b2sums=('adbeeec692c1d41becbdb4295c5ff862b6954c9c7776664965a6d54943847d3cf7bb6fa725cd1607ef9d8ae301bf7eb0e16c56c09da3600669b95994d1ef2611')

_cargo_jobs() {
  local threads
  threads="$(nproc 2>/dev/null)"
  if [[ ! "$threads" =~ ^[1-9][0-9]*$ ]]; then
    threads=2
  fi

  local jobs=$((threads / 2))
  if ((jobs < 1)); then
    jobs=1
  fi
  printf '%s' "$jobs"
}

prepare() {
  cd "$srcdir/Auto-Clicker-$_commit"
  cargo fetch --locked
}

build() {
  cd "$srcdir/Auto-Clicker-$_commit"
  CARGO_BUILD_JOBS="$(_cargo_jobs)" \
    CARGO_TARGET_DIR=target cargo build --frozen --release
}

check() {
  cd "$srcdir/Auto-Clicker-$_commit"
  CARGO_BUILD_JOBS="$(_cargo_jobs)" \
    CARGO_TARGET_DIR=target cargo test --frozen --release --all-targets
  bash tests/qml-smoke.sh target/release/klickmeister
}

package() {
  cd "$srcdir/Auto-Clicker-$_commit"
  install -Dm755 target/release/klickmeister "$pkgdir/usr/bin/klickmeister"
  install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
  install -Dm644 packaging/io.github.jerry0205.klickmeister.desktop \
    "$pkgdir/usr/share/applications/io.github.jerry0205.klickmeister.desktop"
  install -Dm644 packaging/io.github.jerry0205.klickmeister.metainfo.xml \
    "$pkgdir/usr/share/metainfo/io.github.jerry0205.klickmeister.metainfo.xml"
  install -Dm644 packaging/icons/io.github.jerry0205.klickmeister.svg \
    "$pkgdir/usr/share/icons/hicolor/scalable/apps/io.github.jerry0205.klickmeister.svg"
}
