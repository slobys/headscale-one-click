#!/bin/sh
pkg="luci-app-passwall"
page_content='<a href="/projects/openwrt-passwall-build/files/releases/packages-24.10/aarch64_generic/passwall_luci/luci-app-passwall_26.3.6-r1_aarch64_generic.ipk">link</a>'
pkg_links="$(echo "$page_content" | grep -o 'href="/projects/openwrt-passwall-build/files/[^"]*'"${pkg}"'_[^"]*\.ipk[^"]*"' | sed 's|^href="||;s|"$||' | head -n1)"
echo "$pkg_links"