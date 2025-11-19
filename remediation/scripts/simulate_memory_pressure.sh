#!/bin/bash
echo "Triggering memory pressure for ${1:-120} seconds..."
stress-ng --vm 2 --vm-bytes 1G --timeout ${1:-120}s &
echo "PID: $! — Kill with: kill $!"
