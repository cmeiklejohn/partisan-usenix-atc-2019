# library
library(ggplot2)

# Read in the input information
data <- read.csv(file="C:\\Users\\chris\\GitHub\\unir\\results\\aggregate.csv", 
                 head=FALSE, sep=",")

# Rename the columns
colnames(data)[2] <- "Backend"
colnames(data)[3] <- "Size"
colnames(data)[4] <- "Operations"
colnames(data)[5] <- "Errors"

# Filter out the pings for the perf data
PerfData = data[data$Size != 0 & data$Size != 16384 & data$Size != 32768 & data$Size != 65536,]

# Copy data
CopyData = data[data$Size < 524288,]

# Plot performance
ggplot(aes(y = log2(Operations), x = Size, colour = Backend), data = PerfData, stat="identity", label="hi") + 
  
  geom_point(aes(shape=Backend)) +
  
  geom_line(aes(linetype=Backend)) +
  
  scale_x_discrete(name = "Object Size (KB)", 
                   expand=c(0.05, 0.1),
                   breaks=c(98304, 131072, 262144, 524288, 1048576, 2097152, 4194304, 8388608, 16777216),
                   labels=c("96", "", "", "512", "1024", "2048", "4096", "8192", "16384"),
                   limits=c(98304, 131072, 262144, 524288, 1048576, 2097152, 4194304, 8388608, 16777216)) +
  
  theme(legend.justification = c(1, 1), legend.position = c(1, 1)) +
  
  theme(axis.text.x = element_text(angle = 90, hjust = 1)) +
  
  ylab("Total Operations (log2)") +
  
  #ggtitle("10:1 Get/Put KVS Workload for 2 minutes with Riak Core")
  ggtitle("Echo between two processes")

# Plot copy penalty
ggplot(aes(y = log2(Operations), x = Size, colour = Backend), data = CopyData, stat="identity", label="hi") + 
  
  geom_point(aes(shape=Backend)) +
  
  geom_line(aes(linetype=Backend)) +
  
  scale_x_discrete(name = "Object Size (KB)", 
                   expand=c(0.05, 0.1),
                   breaks=c(0, 32768, 65536, 98304),
                   labels=c("0", "32", "64", "96"),
                   limits=c(0, 32768, 65536, 98304)) +
  
  theme(legend.justification = c(1, 1), legend.position = c(1, 1)) +
  
  ylab("Total Operations (log2)") +
  
  ggtitle("10:1 Get/Put KVS Workload for 2 minutes with Riak Core")

# Plot performance
ggplot(aes(y = log2(Operations), x = Size, colour = Backend), data = PerfData, stat="identity", label="hi") + 
  
  geom_point(aes(shape=Backend)) +
  
  geom_line(aes(linetype=Backend)) +
  
  scale_x_discrete(name = "Object Size (KB)", 
                   expand=c(0.05, 0.1),
                   breaks=c(98304, 524288, 1048576, 2097152, 4194304, 8388608, 16777216),
                   labels=c("96", "512", "1024", "2048", "4096", "8192", "16384"),
                   limits=c(98304, 524288, 1048576, 2097152, 4194304, 8388608, 16777216)) +
  
  theme(legend.justification = c(1, 1), legend.position = c(1, 1)) +
  
  ylab("Total Operations (log2)") +
  
  ggtitle("10:1 Get/Put KVS Workload for 2 minutes with Riak Core")

# Plot errors
ggplot(aes(y = Errors, x = Size, colour = Backend), data = PerfData, stat="identity", label="hi") + 
  
  geom_point(aes(shape=Backend)) +
  
  geom_line(aes(linetype=Backend)) +
  
  scale_x_discrete(name = "Object Size (KB)", 
                   expand=c(0.05, 0.1),
                   breaks=c(98304, 524288, 1048576, 2097152, 4194304, 8388608, 16777216),
                   labels=c("96", "512", "1024", "2048", "4096", "8192", "16384"),
                   limits=c(98304, 524288, 1048576, 2097152, 4194304, 8388608, 16777216)) +
  
  theme(legend.justification = c(1, 1), legend.position = c(1, 1)) +
  
  ylab("Errors") +
  
  ggtitle("10:1 Get/Put KVS Workload for 2 minutes with Riak Core")