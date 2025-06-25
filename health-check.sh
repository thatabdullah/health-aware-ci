#!/bin/bash

set -e

if [ -z "$PROMETHEUS_URL" ] || [ -z "$SERVER_B_IP" ]; then
    echo "environment variables PROMETHEUS_URL and SERVER_B_IP must be set"
    exit 1
fi

INSTANCE="${SERVER_B_IP}:9100"
CPU_THRESHOLD="${CPU_THRESHOLD:-80}" # default value
MEM_THRESHOLD="${MEM_THRESHOLD:-20}" # default value
HOST_UP_QUERY="up{instance=\"${INSTANCE}\"}"
CPU_USAGE_QUERY="100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\",instance=\"${INSTANCE}\"}[5m])) * 100)"
MEMORY_AVAILABLE_QUERY="node_memory_MemAvailable_bytes{instance=\"${INSTANCE}\"} / node_memory_MemTotal_bytes{instance=\"${INSTANCE}\"} * 100"

prometheus_query() {
    local query="$1"
    local result
    result=$(curl -s -G "$PROMETHEUS_URL/api/v1/query" --data-urlencode "query=$query" \
  | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "error with query")
    echo "$result"
}

HOST_UP=$(prometheus_query "$HOST_UP_QUERY")
CPU_USAGE=$(prometheus_query "$CPU_USAGE_QUERY")
MEMORY_AVAILABLE=$(prometheus_query "$MEMORY_AVAILABLE_QUERY")

for metric in "$HOST_UP" "$CPU_USAGE" "$MEMORY_AVAILABLE"; do
    if [ "$metric" == "error with query" ]; then
        echo "Error with query"
        exit 1
    fi
done

if [ "$HOST_UP" != "1" ]; then
    echo "Host is down"
    exit 1
else
    echo "Host is up"    
fi


if (( $(echo "$CPU_USAGE > $CPU_THRESHOLD" | bc -l) )); then
    echo "High CPU usage: $CPU_USAGE%"
    exit 1
else
    echo "CPU usage is normal: $CPU_USAGE%"
fi

if (( $(echo "$MEMORY_AVAILABLE < $MEM_THRESHOLD" | bc -l) )); then
    echo "Low memory available: $MEMORY_AVAILABLE%"
    exit 1
else
    echo "Memory available is normal: $MEMORY_AVAILABLE%"
fi

echo "All metrics are within acceptable limits .. proceeding with the deployment"