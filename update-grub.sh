#!/bin/bash
set -euo pipefail

kernel="${1:-}"
[ -z "$kernel" ] && exit 0

config_file="$(find /boot/grub* -maxdepth 1 -name grub.cfg 2>/dev/null | head -n 1)"
[ -n "$config_file" ] || exit 0

deflt_file="$(find /etc/default \( -name grub -o -name grub2 \) 2>/dev/null | head -n 1)"
[ -n "$deflt_file" ] || exit 0

if command -v grub-mkconfig >/dev/null 2>&1; then
	grub-mkconfig -o "$config_file" >/dev/null 2>&1 || true
fi

entry_id="$(grep -m 1 "menuentry .*${kernel}" "$config_file" | grep -oP "\\\$menuentry_id_option '\K[^']+" || true)"
if [ -n "$entry_id" ]; then
	sed -i "s@^\(GRUB_DEFAULT=\).*@\1\"${entry_id}\"@" "$deflt_file"
	grub-mkconfig -o "$config_file" >/dev/null 2>&1 || true
	exit 0
fi

index=0
while IFS= read -r line; do
	case "$line" in
		*menuentry*"${kernel}"*)
			sed -i "s@^\(GRUB_DEFAULT=\).*@\1\"${index}\"@" "$deflt_file"
			grub-mkconfig -o "$config_file" >/dev/null 2>&1 || true
			exit 0
			;;
		*menuentry*)
			index=$((index + 1))
			;;
	esac
done < "$config_file"

echo "WARNING: kernel ${kernel} not found in ${config_file}" >&2
exit 1
