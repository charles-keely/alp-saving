   #!/bin/bash
   EMAIL="charles.daze@icloud.com"
   SUBJECT="Suspicious Activity Alert"
   LOGFILE="/var/log/auth.log"
   MESSAGE="/tmp/suspicious_activity_message.txt"

   # Check for failed login attempts
   if grep "Failed password" $LOGFILE | tail -n 1; then
       echo "Subject: $SUBJECT" > $MESSAGE
       echo "Suspicious activity detected in auth.log:" >> $MESSAGE
       grep "Failed password" $LOGFILE | tail -n 5 >> $MESSAGE
       mail -s "$SUBJECT" "$EMAIL" < $MESSAGE
       rm $MESSAGE
   fi