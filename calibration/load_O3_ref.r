### Load Ozone Reference Data ###
load_ozone <- function(){
    ref_files <- list.files(paste(shared.drive, 'Data/calibration', sep = '/'), pattern = 'Integrated_Monitors_Ozone', full.names = T)
    ref_data <- lapply(ref_files, function(x){
        read.table(x, na.strings = c('','NA','NaN'), skip = 2, header = F, sep = ',', col.names = c('obs_num', 'time', 'voltage', '', '', '')) %>%
        transmute(
            time = mdy_hms(time, tz = 'America/Los_Angeles'),
            ref.o3 = 1000*voltage/2
            )
    })
    ref_data <- do.call(rbind, ref_data)
    return(ref_data)
}

ref_o3 <- load_ozone()
