# crontab for mtpolicyd default tasks
0 1-23 * * * mtpolicyd /usr/bin/mtpolicyd --cron hourly
0 0 2-31 * 1-6 mtpolicyd /usr/bin/mtpolicyd --cron hourly,daily
0 0 2-31 * 0 mtpolicyd /usr/bin/mtpolicyd --cron hourly,daily,weekly
0 0 1 * * mtpolicyd /usr/bin/mtpolicyd --cron hourly,daily,weekly,monthly
