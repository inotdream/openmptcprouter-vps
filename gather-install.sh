#!/bin/sh
#
# Gather VPS image/bootstrap entrypoint.
#
# Use this wrapper for HEXUN/Gather managed OMR nodes instead of invoking the
# upstream installer directly. It pins the product defaults expected by the
# cloud platform while keeping the upstream script as the implementation.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RAW_BASE=${GATHER_VPS_RAW_BASE:-https://raw.githubusercontent.com/inotdream/openmptcprouter-vps/develop}

# Gather production image default:
# 6.12 has been observed not aggregating reliably on current nodes. Debian 12
# ships a maintained 6.1 kernel, so use 6.1 by default. Use 6.6 only with
# pinned kernel deb URLs and a passing gather-mptcp-check result.
: "${KERNEL:=6.1}"
: "${SHADOWSOCKS:=yes}"
: "${SHADOWSOCKS_GO:=yes}"
: "${GLORYTUN_TCP:=yes}"
: "${GLORYTUN_UDP:=yes}"
: "${MQVPN:=yes}"
: "${OPENVPN:=yes}"
: "${DSVPN:=yes}"
: "${WIREGUARD:=yes}"

: "${GATHER_DEFAULT_VPN:=glorytun_tcp}"
: "${GATHER_DEFAULT_PROXY:=shadowsocks-rust}"
: "${GATHER_MPTCP_PROFILE:=balanced}"
: "${GATHER_KERNEL_IMAGE_DEB_URL:=}"
: "${GATHER_KERNEL_HEADERS_DEB_URL:=}"

# Set OMR_ADMIN_REPO/OMR_ADMIN_VERSION to the Gather-patched vps-admin commit
# that contains /traffic before building production images.
: "${OMR_ADMIN_SOURCE:=yes}"
: "${OMR_ADMIN_REPO:=Ysurac/openmptcprouter-vps-admin}"
: "${OMR_ADMIN_VERSION:=develop}"

export KERNEL SHADOWSOCKS SHADOWSOCKS_GO GLORYTUN_TCP GLORYTUN_UDP MQVPN OPENVPN DSVPN WIREGUARD
export GATHER_DEFAULT_VPN GATHER_DEFAULT_PROXY GATHER_MPTCP_PROFILE
export GATHER_KERNEL_IMAGE_DEB_URL GATHER_KERNEL_HEADERS_DEB_URL
export OMR_ADMIN_SOURCE OMR_ADMIN_REPO OMR_ADMIN_VERSION

fetch_file() {
    url="$1"
    dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 --connect-timeout 15 -o "$dest" "$url"
        return $?
    fi
    wget -O "$dest" "$url"
}

echo "Gather VPS bootstrap"
echo "  kernel: ${KERNEL}"
echo "  default vpn/proxy: ${GATHER_DEFAULT_VPN} / ${GATHER_DEFAULT_PROXY}"
echo "  mptcp profile: ${GATHER_MPTCP_PROFILE}"
echo "  omr-admin: ${OMR_ADMIN_REPO}@${OMR_ADMIN_VERSION}"
if [ -n "$GATHER_KERNEL_IMAGE_DEB_URL" ]; then
    echo "  kernel deb: pinned URL"
else
    echo "  kernel deb: Debian bookworm-backports lookup"
fi

if [ ! -s "${SCRIPT_DIR}/debian12-x86_64.sh" ]; then
    echo "  fetching installer body: ${RAW_BASE}/debian9-x86_64.sh"
    fetch_file "${RAW_BASE}/debian9-x86_64.sh" "${SCRIPT_DIR}/debian12-x86_64.sh"
    chmod 0755 "${SCRIPT_DIR}/debian12-x86_64.sh" || true
fi

if [ ! -s "${SCRIPT_DIR}/gather-mptcp-check.sh" ]; then
    echo "  fetching mptcp check: ${RAW_BASE}/gather-mptcp-check.sh"
    fetch_file "${RAW_BASE}/gather-mptcp-check.sh" "${SCRIPT_DIR}/gather-mptcp-check.sh" || true
    chmod 0755 "${SCRIPT_DIR}/gather-mptcp-check.sh" 2>/dev/null || true
fi

if [ -s "${SCRIPT_DIR}/gather-mptcp-check.sh" ]; then
    install -m 0755 "${SCRIPT_DIR}/gather-mptcp-check.sh" /usr/local/sbin/gather-mptcp-check || true
fi

set +e
"${SCRIPT_DIR}/debian12-x86_64.sh" "$@"
rc=$?
set -e

if [ -x /usr/local/sbin/gather-mptcp-check ]; then
    echo "Gather MPTCP capability check (current boot):"
    /usr/local/sbin/gather-mptcp-check || true
    echo "Run gather-mptcp-check again after rebooting into the installed kernel."
fi

exit "$rc"
