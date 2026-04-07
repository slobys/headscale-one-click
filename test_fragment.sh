        log "检查目录: $(echo "$dir_url" | sed 's|https://||')"
        
        local page_content
        if ! page_content="$(wget -qO- "$dir_url" 2>/dev/null)"; then
            warn "无法访问目录页面"
            continue
        fi
        
        # 查找包含包名的链接（可能以 /stats/timeline 结尾）
        local pkg_links
        pkg_links="$(echo "$page_content" | grep -o 'href="/projects/openwrt-passwall-build/files/[^"]*'"${pkg}"_[^"]*\.ipk[^"]*"' | sed 's|^href="||;s|"$||' | head -n1)"
        
        if [ -z "$pkg_links" ]; then
            warn "未找到包: $pkg"
            continue
        fi
        
        # 修复链接：如果包含 /stats/timeline，去掉它
        local clean_link="$pkg_links"
        if echo "$clean_link" | grep -q "/stats/timeline$"; then
            clean_link="$(echo "$clean_link" | sed 's|/stats/timeline$||')"
