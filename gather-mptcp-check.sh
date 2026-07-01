#!/bin/sh
#
# Gather MPTCP capability self-check.
# Run after provisioning or after rebooting into a new kernel.

set -eu

require_bpf="${GATHER_REQUIRE_BPF_SCHEDULERS:-yes}"
kernel="$(uname -r 2>/dev/null || echo unknown)"
api="none"
enabled="0"
scheduler=""
available=""
bpf_objects=""
bpftool_present="no"
balanced="unsupported"
reliable="unsupported"
roundrobin="unsupported"

has_word() {
	case " $1 " in
		*" $2 "*) return 0 ;;
		*) return 1 ;;
	esac
}

object_status() {
	name="$1"
	object="$2"

	if has_word "$available" "$name"; then
		echo "supported"
	elif [ -f "/usr/share/bpf/scheduler/${object}" ]; then
		echo "installed_not_registered"
	else
		echo "missing"
	fi
}

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

command -v bpftool >/dev/null 2>&1 && bpftool_present="yes"

case "$api" in
	v1)
		balanced="$(object_status bpf_burst mptcp_bpf_burst.o)"
		reliable="$(object_status bpf_red mptcp_bpf_red.o)"
		roundrobin="$(object_status bpf_rr mptcp_bpf_rr.o)"
		;;
	v0)
		if has_word "$available" blest || has_word "$available" default; then
			balanced="supported"
		fi
		has_word "$available" redundant && reliable="supported"
		(has_word "$available" roundrobin || has_word "$available" rr) && roundrobin="supported"
		;;
esac

cat <<EOF
kernel=${kernel}
mptcp_api=${api}
mptcp_enabled=${enabled}
current_scheduler=${scheduler}
available_schedulers=${available}
bpf_scheduler_objects=${bpf_objects}
bpftool=${bpftool_present}
bpf_required=${require_bpf}
profile_balanced=${balanced}
profile_reliable=${reliable}
profile_roundrobin=${roundrobin}
EOF

if [ "$api" = "none" ] || [ "$enabled" = "0" ]; then
	echo "result=fail"
	exit 1
fi

if [ "$api" = "v1" ] && [ "$require_bpf" = "yes" ] && [ "$balanced" != "supported" ]; then
	echo "result=fail"
	echo "reason=bpf_burst_not_registered"
	exit 1
fi

if [ "$balanced" != "supported" ]; then
	echo "result=warn"
	exit 2
fi

echo "result=ok"
