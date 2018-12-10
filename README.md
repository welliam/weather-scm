compile:
csc weather.scm

set up db:
THIS_DIRECTORY/weather --initialize

set up cron tab:
*/5 * * * * THIS_DIRECTORY/weather $(PATH_TO_GET_VALUES)
30  5 * * * THIS_DIRECTORY/weather --email

set up environment variables:
export WEATHER_URL="smtp://smtp.gmail.com:587"
export WEATHER_FROM="EMAIL@gmail.com"
export WEATHER_TO="TO@gmail.com"
export WEATHER_CREDENTIALS="EMAIL@gmail.com:PASSWORD"
export WEATHER_SUBJECT="Previous 24 hours of data"