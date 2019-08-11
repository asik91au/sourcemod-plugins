#!/bin/bash    
pkill -9 tail      
GUID="EXEC0f8fad5bd9cb469fa16570867728950e"    
 
tail -f -n1 ./screenlog.0 | awk -v guid="$GUID" '$0 ~ guid { fflush(); system("echo Restarting >> ./screenlog.0; ./serverrun.sh") }'&