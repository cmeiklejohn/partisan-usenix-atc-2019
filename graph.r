# library
library(ggplot2)

# Read in the input information
data <- read.csv(file="C:\\Users\\chris\\OneDrive\\Desktop\\Results\\partisan-bench.csv", 
                 head=FALSE, sep=",")

# Rename the columns
colnames(data)[1] <- "Backend"
colnames(data)[2] <- "Concurrency"
colnames(data)[3] <- "Connections"
colnames(data)[4] <- "Size"
colnames(data)[5] <- "NumMessages"
colnames(data)[6] <- "Latency"
colnames(data)[7] <- "Time"

# Select optimal Partisan configuration and base Disterl configuration
df = data[data$Size == 8388608 & data$Latency == 1 &
       (
         (data$Backend == "disterl" & data$Connections == 1) | 
          (data$Backend == "partisan" & 
             (data$Concurrency == data$Connections))),]

# Plot performance
ggplot(aes(y = (Time / 1000 / 1000), x = Concurrency, colour = Backend), data = df, stat="identity") +
  geom_point(aes(shape=Backend)) +
  geom_line(aes(linetype=Backend)) + 
  xlab("Concurrent Processes") +
  ylab("Time (ms)") +
  theme(legend.justification = c(1, 1), legend.position = c(1, 0.2)) +
  theme(axis.text.x = element_text(angle = 0, hjust = 1)) +
  ggtitle("8MB object with 1ms RTT latency")