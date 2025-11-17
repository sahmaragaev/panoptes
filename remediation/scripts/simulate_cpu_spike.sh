#!/bin/bash
echo "Triggering CPU spike for ${1:-120} seconds..."
stress-ng --cpu $(nproc) --timeout ${1:-120}s &
echo "PID: $! — Kill with: kill $!"
