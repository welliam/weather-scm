set title charttitle
set term png
set output outputfile

set yrange [0:100]
set y2range [0:100]

set timefmt "%s"
set format x "%H:%M"
set y2tics border
set xtics border
set ylabel "Temperature (F)"
set y2label "Humidity"

set xdata time
set style data lines

plot inputfile using 1:2 t "temperature", "" using 1:3 t "humidity"
