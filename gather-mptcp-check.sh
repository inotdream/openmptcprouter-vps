#!/bin/sh
#
# Gather MPTCP capability self-check.
# Run after provisioning or after rebooting into a new kernel.

set -eu

kernel="$(uname -r 2>/dev/null || echo unknown)"
api="none"
enabled="0"
scheduler=""
available=""
bpf_objects=""

if [ -f /proc/sys/net/mptcp/enabled ]; then
	api="v1"
	enabled="$(cat /proc/sys/net/mptcp/enabled 2>/dev/null || echo 0)"
	[ -f /proc/sys/net/mptcp/scheduler ] && scheduler="$(cat /proc/sys/net/mptcp/scheduler 2>/dev/null || true)"
	[ -f /proc/sys/net/mptcp/available_schedulers ] && available="$(cat /proc/sys/net/mptcp/available_schedulers 2>/dev/null || true)"
elif [ -f /proc/sys/net/mptcp/mptcp_enabled ]; then
	api="v0"
	enabled="$(cat /proc/sys/net/mptcp/mptcp_enabled 2>/dev/null || echo 0)"
	[ -f /proc/sys/net/mptcp/mptcp_scheduler ] && scheduler="$(cat /proc/sys/net/mptcp/mptcp_scheduler 2>/dev/null || true)"
	[ -f /proc/sys/net/mptcp/available_schedulers ] && available="$(cat /proc/sys/net/mptcp/available_schedulers 2>/dev/null || true)"
fi

if [ -d /usr/share/bpf/scheduler ]; then
	bpf_objects="$(find /usr/share/bpf/scheduler -maxdepth 1 -type f -name '*.o' -printf '%f ' 2>/dev/null | sed 's/[[:space:]]*$//')"
fi

balanced="unsupported"
reliable="unsupported"
roundrobin="unsupported"

case "$api" in
	v1)
		echo "$available $bpf_objects" | grep -q 'bpf_burst\|mptcp_bpf_burst.o' && balanced="supported"
		echo "$available $bpf_objects" | grep -q 'bpf_red\|mptcp_bpf_red.o' && reliable="supported"
		echo "$available $bpf_objects" | grep -q 'bpf_rr\|mptcp_bpf_rr.o' && roundrobin="supported"
		;;
	v0)
		echo "$available" | grep -q 'blest\|default' && balanced="supported"
		echo "$available" | grep -q 'redundant' && reliable="supported"
		echo "$available" | grep -q 'roundrobin\|rr' && roundrobin="supported"
		;;
esac

cat <<EOF
kernel=${kernel}
mptcp_api=${api}
mptcp_enabled=${enabled}
current_scheduler=${scheduler}
available_schedulers=${available}
bpf_scheduler_objects=${bpf_objects}
profile_balanced=${balanced}
profile_reliable=${reliable}
profile_roundrobin=${roundrobin}
EOF

if [ "$api" = "none" ] || [ "$enabled" = "0" ]; then
	echo "result=fail"
	exit 1
fi

if [ "$balanced" = "unsupported" ]; then
	echo "result=warn"
	exit 2
fi

echo "result=ok"
