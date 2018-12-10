(module weather-utils (has-argument?
                       get-argument
                       get-temporary-path
                       lines
                       words
                       path)
  (import chicken scheme)
  (use extras)
  (use posix)
  (use srfi-1)
  (import weather-config)

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
    (and search (cadr search))))

(module weather-database (create-table insert-current-weather get-last-24-hours)
  (import chicken scheme)
  (use data-structures)
  (use srfi-1)
  (use sqlite3)
  (use posix)
  (import weather-config)
  (import weather-utils)

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

  (define (insert-current-weather)
    (execute
     (get-database)
     "insert into weather (temperature, humidity, created, location) values (?, ?, ?, ?)"
     (get-argument "temperature")
     (get-argument "humidity")
     (current-seconds)
     "inside"))

  (define (get-last-24-hours)
    ;; temperature, humidity, created, location
    (map-row
     list
     (get-database)
     "select temperature, humidity, created, location from weather where created >= ? and created < ? order by created"
     (- (current-seconds) (* 60 60 24))
     (current-seconds))))

(module weather-dump-data (dump-data)
  (import chicken scheme)
  (use data-structures)
  (import weather-utils)
  (import weather-database)

  (define (dump-data)
    (define data (get-last-24-hours))
    (define path (get-temporary-path "dat"))
    (with-output-to-file path
      (lambda ()
        (for-each (lambda (row)
                    (define temperature (->string (car row)))
                    (define humidity (->string (cadr row)))
                    (define created (->string (caddr row)))
                    (display
                     (string-append created " " temperature " " humidity "\n")))
                  data)))
    path))

(module weather-chart (write-chart)
  (import chicken scheme)
  (import weather-dump-data)
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

  (define (write-chart)
    (define title "Weather")
    (define output (get-temporary-path "png"))
    (define input (dump-data))
    (write-chart-with title output input)
    output))

(module weather-email (send-email
                       format-email
                       get-environment-email-context)
  (import chicken scheme)
  (use srfi-1)
  (use posix)
  (use base64)
  (use shell)
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

  (define (format-email path-to-chart-png context)
    (define cid "chart")
    (define html-body
      (format "<html><body><img src=\"cid:~a\" /></body></html>"
              cid))
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

    (define (send-email path-to-chart-png context)
      (define message-path (get-temporary-path "txt"))
      (with-output-to-file message-path
        (lambda () (print (format-email path-to-chart-png context))))
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

  (define (send-last-24-hours)
    (define path (write-chart))
    (define context (get-environment-email-context))
    (send-email path context))

  (define (main)
    (cond
     ((has-argument? "email") (send-last-24-hours))
     ((has-argument? "initialize") (create-table))
     ((and (has-argument? "temperature")
           (has-argument? "humidity"))
      (insert-current-weather))
     (else (print "Unknown arguments")))))

(import main)
(main)
