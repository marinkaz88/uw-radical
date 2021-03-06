source('config.r', encoding = 'UTF8')
source('getMESA_data_Kairos.r', encoding = 'UTF8') # get sensor data from Kairos



#filelist <- str_subset(list.files(paste0(shared.drive, 'Data/calibration/NYC_reference_data'), full.names = T), '\\.csv$')
#ref_nyc <- lapply(filelist, function(x){read.csv(x, stringsAsFactors = F, check.names = F, na.strings = c('', 'NA', 'NoData', '<Samp', 'OffScan', 'InVld', 'RS232'))}) %>% bind_rows()


#filelist <- list.files("X:\\Data\\calibration\\NYC_reference_data", pattern = '\\.xls', full.names = T)
filelist <- list.files("X:\\Data\\calibration\\NYC_reference_data", pattern = 'NYC_[0-9]+\\.csv', full.names = T)
result <- list()
for( file in filelist ){
    header <- sapply(
        #xlsx::read.xlsx(file, 1, startRow = 2, endRow = 3, header = F, stringsAsFactors = F), #read to row 4 if you want units included in colnames
        read.csv(file, skip = 1, nrows = 2, header = F, stringsAsFactors = F), #read to row 4 if you want units included in colnames
        function(x){str_replace(paste(x, collapse = '_'), ' ', '')}
    )
    #result[[file]] <- xlsx::read.xlsx(file, 1, startRow = 5, header = F, stringsAsFactors = F)
    result[[file]] <- read.csv(file, skip = 4, header = F, stringsAsFactors = F)
    result[[file]] <- result[[file]][ 1:(nrow(result[[file]])-10), ] #get rid of the summary
    names(result[[file]]) <- str_replace(header, '_$', '')
}
ref_nyc <- do.call(rbind, result)


ref_nyc <- ref_nyc %>%
    mutate(
        #datetime = mdy_hm(datetime, tz = 'EST'),
        datetime = mdy_hm(paste(Date, Time), tz = 'US/Eastern'),
        row = row_number()
        ) %>%
    select(-Date, -Time) %>% 
    #select(-`_`) %>%
    gather(measurement, value, -datetime, -row, na.rm = T) %>%
    mutate(measurement = str_replace_all(measurement, ' ', '')) %>%
    separate(measurement, c('site', 'poll'), sep = '_') %>%
    mutate(
        poll = if_else(poll == 'PM25C', 'PM25FEM', poll),
        value = as.numeric(value),
        siteid = if_else(
            site == 'NYBG', 
            'N003', 
            if_else(
                site == 'IS52', 
                'N001', 
                if_else(
                    site == 'PS19', 
                    'N005',
                    if_else(
                        site == 'CCNY', 
                        'N004', 
                        if_else(
                            site == 'DivisionStreet', 
                            'N006', 
                            NA_character_
                            )
                        )
                    )
                )
            )
        )

#
# Site -> Location Match-up
# -------------------------
siteloc <- read.csv(paste0(shared.drive, "\\Data\\SensorLocationTable.csv")) %>%
    mutate(
        start_time = mdy_hm(start_time, tz = 'US/Eastern'),
        end_time = mdy_hm(end_time, tz = 'US/Eastern')
        ) %>%
    mutate(
        start_time = if_else(is.na(start_time), mdy_hm('01-01-1900 00:00', tz = 'US/Eastern'), start_time),
        end_time   = if_else(is.na(end_time),   mdy_hm('01-01-2099 00:00', tz = 'US/Eastern'),   end_time)
        )
        

ref_nyc <- ref_nyc %>%
    inner_join(siteloc, by = 'siteid') %>%
    filter(datetime >= start_time & datetime <= end_time) %>%
    rename(sensor = monitor) %>% 
    select(datetime, poll, value, sensor)


#avg by 10 minutes
#ref_nyc_10min <- ref_nyc %>%
#    mutate(time.bin = floor_date(with_tz(datetime, 'UTC'), unit = '10 minutes')) %>%
#    group_by(sensor, time.bin, poll) %>%
#    summarize(ref_value = mean(value, na.rm=T)) %>%
#    ungroup()


average.sensor.measurements <- function(df, avg_period){
    df %>%
        mutate(time.bin = floor_date(date, unit = avg_period)) %>%
        group_by(monitor, time.bin) %>%
        summarize_if(is.numeric, function(x){mean(x, na.rm=T)}) %>%
        ungroup()
}
# get sensor data
suppressWarnings(suppressMessages(sensor_data <- getMESA_data(start.date = ymd_hm('2017-03-01 00:00'), stop.date = ymd_hm('2017-07-10 23:59'))))
sensor_data_long <- sensor_data$long %>% mutate(value = as.numeric(value))

ref_col <- c(
    'CO_sensor'             = 'CO',
    'O3_sensor'             = 'O3',
    'NO_sensor'             = 'NO',
    'NO2_sensor'            = 'NO2',
    'S1_val'                = 'PM25FEM',
    'S2_val'                = 'PM25FEM',
    'Plantower1_pm2_5_mass' = 'PM25FEM',
    'Plantower2_pm2_5_mass' = 'PM25FEM'
)

sensor_data_long <- sensor_data_long %>% filter(tags %in% names(ref_col))

sensor_data_long_60min <- sensor_data_long %>%
    mutate(time.bin = floor_date(date, unit = '60 minutes')) %>%
    select(-date) %>%
    group_by(monitor, time.bin, tags) %>%
    summarize(sensor_value = mean(value, na.rm=T)) %>%
    ungroup() %>%
    mutate(poll = ref_col[as.character(tags)])
sensor_data_60min <- average.sensor.measurements(sensor_data$wide, '60 minutes')

compare <- inner_join(sensor_data_long_60min, ref_nyc, by = c('monitor'='sensor', 'time.bin'='datetime', 'poll'))
#compare %>% group_by(poll) %>% summarize(r2 = cor(sensor_value, ref_value)**2)

compare <- rename(compare, sensor = monitor, ref_value = value) 

#sitename <- list()
#rawdata <- list()
#column_names <- list()
#temp <- c("sitename" = sitename, "rawdata" = rawdata, "column_names" = column_names)


#result <- list()
#temp   <- list()
#clean.data <- as.data.frame(matrix(NA, nrow=0, ncol = 5))
#names(clean.data) <- c("datetime", "O3", "NO2", "CO", "PM25", "NO")
#for (i in 1:length(filelist)){
#  temp <- list("sitename" = sitenames[i],
#                 "rawdata"  = as.data.frame(read.xls(filelist[i], skip = 4, header = FALSE)),
#                  "column_names" = read.xls(filelist[i], header = FALSE)[2,] )
#  temp$rawdata$datetime <- strptime( as.character(temp$rawdata$V1), format="%m/%d/%Y %I:%M %p", tz="EST")
#  temp2 <- as.data.frame(matrix(-99.99, nrow=dim(temp$rawdata)[1], ncol=4))
#  names(temp2) <- names(clean.data)[-1]
#  data.miss <- names(temp2)[!(names(temp2) %in% names(temp$rawdata))]
#  temp$rawdata[,data.miss] <- temp2[data.miss]
#  result[[i]] <- temp
#  clean.data <- rbind.data.frame(clean.data, temp$rawdata[,c("datetime","O3","NO2","CO","PM25", "NO")])
#}

#clean.data <- as.data.frame(matrix(NA, nrow=0, ncol = 7))
#names(clean.data) <- c("datetime", "sitename", "O3", "NO2", "CO", "PM25", "NO")
#clean.data$datetime <- as.Date(clean.data$datetime)
#clean.data$O3 <- as.numeric(clean.data$O3)
#clean.data$PM25 <- as.numeric(clean.data$PM25)
#clean.data$NO2 <- as.numeric(clean.data$NO2)
#clean.data$CO <- as.numeric(clean.data$CO)
#clean.data$NO <- as.numeric(clean.data$NO)
#clean.data$sitename <- as.character(clean.data$sitename)
#for (i in 1:length(filelist)){
#  temp <- read.xls(filelist[i], stringsAsFactors = FALSE)
#  temp$datetime <- as.POSIXct(strptime( as.character(temp$date1), format="%m/%d/%Y %I:%M %p", tz="EST"))
#  temp$sitename <- rep(sitenames[i], length(temp$datetime))
#  clean.data <- rbind.data.frame(clean.data, temp[,c("datetime","sitename","O3","NO2","CO","PM25", "NO")])
#}
# clean.data$O3 <- as.numeric(clean.data$O3)
# clean.data$PM25 <- as.numeric(clean.data$PM25)
# clean.data$NO2 <- as.numeric(clean.data$NO2)
# clean.data$CO <- as.numeric(clean.data$CO)
# clean.data$NO <- as.numeric(clean.data$NO)
# summary(clean.data)

#setwd(current.wd)
