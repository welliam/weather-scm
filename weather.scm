(declare (uses weather-config))

(module weather-utils (has-argument?
                       get-argument
                       get-temporary-path
                       lines
                       words
                       current-date-formatted
                       make-weather
                       weather?
                       one-day
                       weather-temperature
                       weather-humidity
                       weather-created
                       weather-location)
  (import chicken scheme)
  (use extras)
  (use posix)
  (use srfi-1)

  (define (current-date-formatted)
    (define time (seconds->local-time))
    (define day (vector-ref time 3))
    (define month (vector-ref time 4))
    (define year (vector-ref time 5))
    (format "~a/~a/~a" month day year))

  (define (sep s . xs)
    (foldr (lambda (x result) (string-append x s result))
           ""
           xs))

  (define (lines . xs)
    (apply sep "\n" xs))

  (define (words . xs)
    (apply sep " " xs))

  (define (get-temporary-path extension)
    (string-append
     "/tmp/weather-"
     (apply string-append
            (map (lambda (x) (number->string (random 10)))
                 (iota 10)))
     "."
     extension))

  (define (has-argument? flag)
    (member (string-append "--" flag)
            (command-line-arguments)))

  (define (get-argument flag)
    (define search (has-argument? flag))
    (and search (cadr search)))

  (define-record-type weather
    (make-weather
     <weather-temperature>
     <weather-humidity>
     <weather-created>
     <weather-location>)
    weather?
    (<weather-temperature> weather-temperature)
    (<weather-humidity> weather-humidity)
    (<weather-created> weather-created)
    (<weather-location> weather-location))

  (define one-day (* 60 60 24)))

(module weather-database (create-table
                          insert-current-weather
                          weather-get-last-days
                          dump-data)
  (import chicken scheme)
  (use data-structures)
  (use srfi-1)
  (use sqlite3)
  (use posix)
  (use extras)
  (import weather-utils)
  (import weather-config)

  (define (get-database)
    (open-database (format "~a/weather.db" config-path)))

  (define (create-table)
    (define db (get-database))
    (execute db "drop table if exists weather")
    (execute db "create table weather
       (id integer primary key,
        created integer not null,
        temperature integer not null,
        humidity integer not null,
        location text not null);"))

  (define (current-weather)
    (make-weather
     (get-argument "temperature")
     (get-argument "humidity")
     (current-seconds)
     "inside"))

  (define (insert-current-weather)
    (define weather (current-weather))
    (execute
     (get-database)
     "insert into weather (temperature, humidity, created, location)
      values (?, ?, ?, ?)"
     (weather-temperature weather)
     (weather-humidity weather)
     (weather-created weather)
     (weather-location weather)))

  (define (weather-get-last-days n)
    ;; temperature, humidity, created, location
    (map-row make-weather
             (get-database)
             "select temperature, humidity, created, location
              from weather
              where created >= ? and created < ? order by created"
             (- (current-seconds) (* n one-day))
             (current-seconds)))

  (define (dump-data data)
    (define path (get-temporary-path "dat"))
    (with-output-to-file path
      (lambda ()
        (for-each (lambda (weather)
                    (printf "~a ~a ~a\n"
                            (+ (weather-created weather) config-timezone)
                            (weather-temperature weather)
                            (weather-humidity weather)))
                  data)))
    path))

(module weather-process (get-data-after
                         get-growth)
  (import chicken scheme)
  (use srfi-1)
  (import weather-utils)

  (define (get-data-after data time)
    (filter (lambda (w) (> (weather-created w) time))
            data))

  (define (latest-before data time)
    (define before
      (filter (lambda (w) (< (weather-created w) time))
              data))
    (and (not (null? before)) (last before)))

  (define (get-growth get-value data before after)
    (define (get x) (and x (get-value x)))
    (define before-value (get (latest-before data before)))
    (define after-value (get (latest-before data after)))
    (and before-value
         after-value
         (* (/ (- after-value before-value)
               before-value)
            100))))

(module weather-chart (write-chart)
  (import chicken scheme)
  (import weather-database)
  (import weather-process)
  (import weather-utils)
  (import weather-config)
  (use shell)
  (use extras)

  (define (write-chart-with title output input)
    (execute
     (list
      (apply string-append
             (list "gnuplot "
                   (format " -e \"charttitle='~a'\" " title)
                   (format " -e \"outputfile='~a'\" " output)
                   (format " -e \"inputfile='~a'\" " input)
                   (format " ~a/chart.plt" config-path))))))

  (define (write-chart data)
    (define title "Weather")
    (define output-path (get-temporary-path "png"))
    (define last-24-hours
      (get-data-after data (- (current-seconds) one-day)))
    (define input (dump-data last-24-hours))
    (write-chart-with title output-path input)
    output-path))

(module weather-email (send-email
                       get-environment-email-context)
  (import chicken scheme)
  (use srfi-1)
  (use posix)
  (use base64)
  (use shell)
  (use extras)
  (import weather-process)
  (import weather-utils)
  (import weather-config)

  (define-record-type email-context
    (email-context <url> <from> <to> <credentials> <subject>)
    email-context?
    (<url> email-context-url)
    (<from> email-context-from)
    (<to> email-context-to)
    (<credentials> email-context-credentials)
    (<subject> email-context-subject))

  (define (get-environment-email-context)
    (define current-env (get-environment-variables))
    (email-context
     config-url
     config-from
     config-to
     config-credentials
     config-subject))

  (define (foldl1 f t) (foldl f (car t) (cdr t)))

  (define (format-html cid data)
    (format "<html>
               <body>
                 <h1>As of ~a</h1>
                 <div>High: ~aF, Low: ~aF</div>
                 <div>Temperature growth: ~a%</div>
                 <div>Humidity growth: ~a%</div>
                 <img src=\"cid:~a\" />
               </body>
             </html>"
            (current-date-formatted)
            (foldl1 max (map weather-temperature data))
            (foldl1 min (map weather-temperature data))
            (get-growth weather-temperature
                           data
                           (- (current-seconds) one-day)
                           (current-seconds))
            (get-growth weather-humidity
                           data
                           (- (current-seconds) one-day)
                           (current-seconds))
            cid))

  (define (format-email data path-to-chart-png context)
    (define cid "chart")
    (define html-body (format-html cid data))
    (lines
     (format "From: Charts ~a" (email-context-from context))
     (format "To: ~a" (email-context-to context))
     (format "Subject: ~a" (email-context-subject context))
     (format "Reply-To: Charts ~a" (email-context-subject context))
     "Cc:"
     "MIME-Version: 1.0"
     "Content-Type: multipart/mixed; boundary=MULTIPART-MIXED-BOUNDARY"
     ""
     "--MULTIPART-MIXED-BOUNDARY"
     "Content-Type: multipart/alternative; boundary=\"MULTIPART-ALTERNATIVE-BOUNDARY\""
     ""
     "--MULTIPART-ALTERNATIVE-BOUNDARY"
     "Content-Type: text/html; charset=utf-8"
     "Content-Transfer-Encoding: base64"
     "Content-Disposition: inline"
     ""
     (base64-encode html-body)
     "--MULTIPART-ALTERNATIVE-BOUNDARY--"
     "--MULTIPART-MIXED-BOUNDARY"
     "Content-Type: image/png"
     "Content-Transfer-Encoding: base64"
     "Content-Disposition: inline"
     (format "Content-Id: <~a>" cid)
     (call-with-input-file path-to-chart-png base64-encode)))

    (define (send-email data path-to-chart-png context)
      (define message-path (get-temporary-path "txt"))
      (with-output-to-file message-path
        (lambda () (print (format-email data path-to-chart-png context))))
      (execute
       (list
        (words "curl"
               (format "-s \"~a\"" (email-context-url context))
               (format "--mail-from \"~a\"" (email-context-from context))
               (format "--mail-rcpt \"~a\"" (email-context-to context))
               (format "--ssl -u \"~a\"" (email-context-credentials context))
               (format "-T \"~a\" -k --anyauth" message-path))))))

(module main (main)
  (import chicken scheme)
  (import weather-utils)
  (import weather-database)
  (import weather-chart)
  (import weather-email)
  (import weather-config)

  (define (send-current-email)
    (define data (weather-get-last-days 2))
    (define path (write-chart data))
    (define context (get-environment-email-context))
    (send-email data path context))

  (define (main)
    (cond
     ((has-argument? "email") (send-current-email))
     ((has-argument? "initialize") (create-table))
     ((and (has-argument? "temperature")
           (has-argument? "humidity"))
      (insert-current-weather))
     (else (print "Unknown arguments")))))

(import main)
(main)
