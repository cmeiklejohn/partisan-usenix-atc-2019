# library
library(ggplot2)

# Read in the input information
data <- read.csv(file="C:\\Users\\chris\\GitHub\\unir\\results\\aggregate.csv", 
                 head=FALSE, sep=",")

# Filter out the pings
Data = data[data$V3 != 0,]

# Partisan 
PartisanOperations = Data[Data$V2 == "partisan", c(4)]
PartisanSize = Data[Data$V2 == "partisan", c(3)]

# Disterl
DisterlOperations = Data[Data$V2 == "disterl", c(4)]
DisterlSize = Data[Data$V2 == "disterl", c(3)]

plot(DisterlSize, DisterlOperations, type="o", 
     col="blue", xlab="Object Size (Bytes)", ylab="Total Operations")
lines(PartisanSize, PartisanOperations, type="o", col="red")