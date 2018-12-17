set up environment weather-config, like:
```
(declare (unit weather-config))

(module weather-config (config-path
                        config-subject
                        config-credentials
                        config-to
                        config-from
                        config-url)
  (import chicken scheme)
  (define config-url "smtp://smtp.gmail.com:587")
  (define config-from "FROM_EMAIL@gmail.com")
  (define config-to "TO_EMAIL@gmail.com")
  (define config-credentials "FROM_EMAIL@gmail.com:PASSWORD")
  (define config-subject "Chart incoming!")
  (define config-path "/path/to/this/directory"))
```

compile:
```
csc -c -j weather-config weather-config.scm
csc -c weather.scm
csc weather-config.o weather.o -o weather
```

set up db:
```THIS_DIRECTORY/weather --initialize```

set up cron tab:
```
*/5 * * * * THIS_DIRECTORY/weather $(PATH_TO_GET_VALUES)
30  5 * * * THIS_DIRECTORY/weather --email
```
