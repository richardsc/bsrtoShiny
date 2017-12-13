rm(list=ls())
library(oce)

findNearest <- function(x, value, na.val=-9999) {
    if (inherits(x, 'POSIXt')) x <- as.numeric(x); value <- as.numeric(value)
    na <- is.na(x)
    x[na] <- na.val
    out <- NULL
    for (i in 1:length(value)) {
        outtmp <- which(abs(x-value[i])==min(abs(x-value[i])))
        if (length(outtmp) > 1) outtmp <- outtmp[1] ## simple way to resolve ties
        out <- c(out, outtmp)
    }
    return(out)
}

dir <- '/data/archive/barrow/2017/bsrto/rdi/'

## Cat all the files together to make one complete one
system('cat /data/archive/barrow/2017/bsrto/rdi/*.rdi > adp.000')

adp <- read.oce('adp.000')

## use pole compass heading instead of ADCP compass by interpolation
load('pc.rda')
t <- adp[['time']]
pct <- pc$startTime
pch <- pc$meanHeading
h <- approx(pct, pch, t)$y

## find the correct pole compass heading by taking the nearest ensemble
hh <- NULL
for (i in seq_along(t)) {
    II <- findNearest(pct, t[i])
    hh[i] <- pch[II]
}

## correct for magnetic declination
lon <- -91.25105
lat <- 74.60635
dec <- magneticField(rep(lon, length(t)), rep(lat, length(t)), t)
hh <- hh + dec$declination

## replace the ADCP compass with the pole compass, corrected for the
## 45 degree alignment of beam 3
adp[['headingOriginal']] <- adp[['heading']]
adp[['heading']] <- hh + 45

## trim bins that are less than 15% of the range to the surface
## (FIXME: not trimming for ice yet)
adp <- subset(adp, distance < max(adp[['pressure']], na.rm=TRUE))
mask <- array(1, dim=c(length(adp[['time']]), length(adp[['distance']])))
for (i in 1:4) {
    for (j in seq_along(adp[['time']])) {
        II <- adp[['distance']] > adp[['pressure']][j]*0.85
        mask[j, II] <- NA
    }
    adp[['v']][,,i] <- adp[['v']][,,i]*mask
}

## If any bins have less than 50% data coverage, just NA them
remove <- NULL
for (j in seq_along(adp[['distance']])) {
    remove <- c(remove,
                ifelse(sum(is.na(adp[['v']][,j,1])) > 0.5*length(adp[['time']]),
                       TRUE, FALSE))
}

adp <- subset(adp, distance %in% distance[!remove])

## convert to ENU coordinates
enu <- toEnu(adp)
enu <- oceSetData(enu, 've', apply(enu[['v']][,,1], 1, mean, na.rm=TRUE))
enu <- oceSetData(enu, 'vn', apply(enu[['v']][,,2], 1, mean, na.rm=TRUE))

save(file='adp.rda', adp)