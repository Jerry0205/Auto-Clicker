# Maintainer: Klickmeister contributors
pkgname=klickmeister
pkgver=0.1.0
pkgrel=1
pkgdesc='Small, safe auto clicker for KDE Plasma Wayland'
arch=('x86_64')
url='https://github.com/jerry0205/Auto-Clicker'
license=('MIT')
depends=('gcc-libs' 'glibc' 'kirigami' 'qt6-base' 'qt6-declarative' 'xdg-desktop-portal' 'xdg-desktop-portal-kde')
makedepends=('cargo' 'clang' 'lld' 'pkgconf' 'qt6-tools' 'rust')
options=('!lto')
source=()
b2sums=()

prepare() {
  cd "$startdir"
  cargo fetch --locked
}

build() {
  cd "$startdir"
  CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-2}" \
    CARGO_TARGET_DIR=target cargo build --frozen --release
}

check() {
  cd "$startdir"
  CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-2}" \
    CARGO_TARGET_DIR=target cargo test --frozen --all-targets
}

package() {
  cd "$startdir"
  install -Dm755 target/release/klickmeister "$pkgdir/usr/bin/klickmeister"
  install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
  install -Dm644 packaging/io.github.jerry0205.klickmeister.desktop \
    "$pkgdir/usr/share/applications/io.github.jerry0205.klickmeister.desktop"
  install -Dm644 packaging/io.github.jerry0205.klickmeister.metainfo.xml \
    "$pkgdir/usr/share/metainfo/io.github.jerry0205.klickmeister.metainfo.xml"
  install -Dm644 packaging/icons/io.github.jerry0205.klickmeister.svg \
    "$pkgdir/usr/share/icons/hicolor/scalable/apps/io.github.jerry0205.klickmeister.svg"
}
