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

data[8] <- paste(data$Backend, data$Latency, "ms", "RTT latency")
colnames(data)[8] <- "Configuration"

# Select optimal Partisan configuration and base Disterl configuration
df = data[data$Size == 8388608 & data$Latency != 100 & 
            (
              (data$Backend == "disterl" & data$Connections == 1) | 
                (data$Backend == "partisan" & 
                   (data$Concurrency == data$Connections))),]

# Plot performance
ggplot(aes(y = (Time / 1000 / 1000), x = Concurrency, colour = Configuration), data = df, stat="identity") +
  geom_point(aes(shape=Configuration)) +
  geom_line(aes(linetype=Backend)) + 
  xlab("Concurrent Processes") +
  ylab("Time (ms)") +
  theme(legend.justification = c(1, 1), legend.position = c(0.3, 0.9)) +
  theme(axis.text.x = element_text(angle = 0, hjust = 1)) +
  ggtitle("echo request/reply with 8MB object")