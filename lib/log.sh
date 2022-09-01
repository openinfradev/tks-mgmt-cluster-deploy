#!/usr/bin/env bash

log_info() {
	echo -e ">\e[1m INFO: $@ \e[0m"
}

log_warn() {
	echo -e ">\e[1m WARNING: $@ \e[0m"
}

log_error() {
	echo -e ">\e[1m ERROR: $@ \e[0m"
	exit 1
}
