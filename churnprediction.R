###Packages#####################
packages <- c("scales", "MASS", "utils", "dplyr", "ggplot2", "lubridate", "mgcv", "data.table")
for (i in packages){
  if (i %in% rownames(installed.packages()) == FALSE)
    install.packages(i)
  library(i, character.only = TRUE)
}
rm(list=ls())
setwd("~/Church_Prediction_Git")

#IMPORTING DATA#####################################################
F5642730 <- fread('F5642730 (2).csv') # Address Number 
colnames(F5642730)[1] <- "AddressNumber"
dfMDRLAPR19 <- fread("MDRLAPR19.csv")
df42119 <- fread("F42119_new.csv", select = c(4,7)) # AddressNumber, Date 
sales <- read.csv("sales.csv")
contacts <- read.csv("Contacts.csv")

#Prepping df42119 for dates################################
df42119 <- data.frame(AddressNumber=df42119$`Address Number`,Date=df42119$`G/L Date`)
df42119$Date <- as.Date(df42119$Date, format = "%m/%d/%Y")

df2 <- data.frame(AddressNumber=df42119$AddressNumber,MinDate=df42119$Date)
df2 <- count(df2,AddressNumber,MinDate)
df2 <- setDT(df2)[order(MinDate), head(.SD, 1L), by = AddressNumber] # Getting earliest date for each customer purchase
df2$MaxDate <- setDT(df42119[,c("AddressNumber","Date")])[order(Date), tail(.SD, 1L), by = AddressNumber][,2] # Getting the last date for customer purchase


###Grades############################
gradesdf <- data.frame(AddressNumber=F5642730$AddressNumber, Grade=F5642730$`Grade Range Description 1`) # Grade
df <- gradesdf
rm(gradesdf)


###Enrollment############################
# Assigns enrollment size based on previous specifications
enrollmentfunc <- function(x,y,xs,s,m,l,xl) {
  if (x=="2" | x=="4" | x=="G"){
    if(y<1000) return(xs)
    if(y>=1000 & y<5000 ) return(s)
    if(y>=5000 & y<15000 ) return(m)
    if(y>=15000 & y<25000 ) return(l)
    if(y>=25000) return(xl)
  } 
  if (x=="S" | x=="V" | 
      x=="P" | x=="C"){
    if(y>=2499) return(xl)
    if (y>=1500 & y<2499) return (l)
    if (y>=500 & y<1500) return (m)
    if (y<500) return (s)
  } 
  if (x=="M" | x=="J"){
    if(y<500) return(s)
    if(y>=500 & y<1000 ) return(m)
    if(y>=1000) return(l)
  }
  if (x=="E"){
    if(y<300) return(s)
    if(y>=300 & y<500 ) return(m)
    if(y>=500 & y<750) return(l)
    if(y>750) return(xl)
  }
  else return("No Grade Range")
  
}

enrolldf <- data.frame(PID = dfMDRLAPR19$PID,Enrollment = dfMDRLAPR19$ENROLLMENT,SchoolType = dfMDRLAPR19$SCHTYPE)
enrolldf <- left_join(enrolldf, data.frame(AddressNumber = F5642730$AddressNumber, PID = F5642730$`PID Number`))
enrolldf <- data.frame(AddressNumber = enrolldf$AddressNumber, Enrollment = enrolldf$Enrollment, SchoolType = enrolldf$SchoolType)
enrolldf <- na.omit(enrolldf) # Removing nas 
enrolldf$SchoolType <- as.character(enrolldf$SchoolType)
# Creating size column and then applying enrollmentfunction
enrolldf$size <- NA 
enrolldf$size <-  as.character(mapply(enrollmentfunc, x=enrolldf$SchoolType,y=enrolldf$Enrollment,
                                      xs="Very Small",s="Small",m="Medium",l="Large",xl="Very Large"))

df <- left_join(df,enrolldf[,c(1,4)])
rm(enrolldf)


###Contracts####################################
# Adding in contract info
contractdf <- data.frame(AddressNumber=F5642730$AddressNumber, Contract = F5642730$`User Defined Text 1`, Start = F5642730$`CBS Date 1`,End = F5642730$`CBS Date 2`)
contractdf$Contract <- as.character(sapply(contractdf[2],function(x) ifelse(x=="","No","Yes")))
contractdf$Start <- as.Date(contractdf$Start, format = "%m/%d/%Y")
contractdf$End <- as.Date(contractdf$End, format = "%m/%d/%Y")
contractdf$length <- contractdf$End-contractdf$Start
contractdf$length[is.na(contractdf$length)] <- 0
contractdf <- contractdf[-c(3,4)]
#Added:
colnames(contacts)[1] <- "AddressNumber"
colnames(contacts)[6] <- "Contract2"
contractdf <- left_join(contractdf,contacts[,c(1,6)])
contractdf$Contract2 <- as.character(contractdf$Contract2)
contractdf$Contract2[is.na(contractdf$Contract2)] <- ""
contractdf$Contract2[!contractdf$Contract2==""] <- "Yes"
contractdf$Contract2[contractdf$Contract2==""] <- "No"
contractdf$FinalContract[contractdf$Contract2=="Yes" | contractdf$Contract=="Yes"] <- "Yes"
contractdf$FinalContract[is.na(contractdf$FinalContract)] <- "No"
df <- left_join(df,contractdf[c(1,5,3)])
#:Added
#df <- left_join(df,contractdf)
rm(contractdf)



###Emails########################
emails <- contacts
colnames(emails)[9] <- "email"
emaildf <- fread("Bronto Email List.csv")
colnames(emaildf)[1] <- "email"
emaildf <- left_join(emaildf,emails[,c(1,9)])
emaildf <- na.omit(emaildf)
emaildf <- unique(emaildf)
colnames(emaildf)[3] <- "AddressNumber"
df <- left_join(df,emaildf[,c(3,2)])
###Cleaning######
df$Grade <- as.character(df$Grade)
df$Grade[df$Grade %in% c("4 Year College", "2 Year College")] <- "University"
df$Grade[df$Grade %in% c("Elemetary School", "Middle School", "High School")] <- "K12"
df$Grade[!(df$Grade %in% c("University", "K12", NA))] <- "Other"


### Final Dataframe prep###################

df2 <- left_join(df2,F5642730[,c(1)])
df2$length <- df2$MaxDate-df2$MinDate
df3 <- df2 #[!df2$length==0,] #This line of code would remove the 1 time purchasers
df3$length <- as.Date("2017-04-12")-df3$MaxDate

#For 1s and 0s churning
df3$churned <- sapply(df3$length, function(x) ifelse(x>0,1,0))
# #For length till churn
# df3$churned <- df3$MaxDate-df3$MinDate

modeldf <- inner_join(df3[,c(1,6)],df)
modeldf <- inner_join(modeldf,df2[,c(1,3)])
modeldf$length[is.na(modeldf$length)] <- 0
modeldf <- na.omit(modeldf)
modeldf <- modeldf[,-1]

modeldf$length <- as.numeric(modeldf$length)
modeldf$Grade <- as.factor(modeldf$Grade)
modeldf$Contract <- as.factor(modeldf$Contract)
modeldf$size <- as.factor(modeldf$size)
modeldf$n <- as.numeric(modeldf$n)
modeldf$Status <- as.factor(modeldf$Status)
colnames(modeldf)[5] <- "ContractLength"
colnames(modeldf)[7] <- "NumPurchasesonDay1"


####
###Removing unneeeded DF's at this point####################
#rm(df,df2,df3)
# Running the model ######################
set.seed(5)
sampsize <- round(nrow(modeldf)*.75)
samp <- sample(nrow(modeldf),sampsize)
dftrain <- modeldf[samp,]
dftest <- modeldf[-samp,]

acclist <- NULL ####List that will contain the accuracy of each model
datlist <- NULL ###List that will show what collumns are being used in the model
minlist <- NULL ###showing the lowest prediction prob for each model
maxlist <- NULL ###Showing the highest prediction prob for each model

ptm <- proc.time()
for (i in 1:6){
  combdf <- combn(colnames(dftrain[2:7]),i)
  for (k in 1:ncol(combdf)){
    train <- dftrain[c("churned",combdf[,k])]
    trainmodel <- glm(churned~.,family= "binomial", data = train, na.action = na.exclude)
    test <- dftest[c("churned", combdf[,k])]
    test <- na.omit(test) ####Added line to try to avoid error
    test$prob <- predict.glm(trainmodel, test, type = "response")
    test$predict <- sapply(test$prob, function(x) ifelse(x>.53,1,0))
    test$acc <- mapply(x = test$predict, y = test$churned, function(x,y) ifelse(x==y,1,0))
    sum(test$acc)/nrow(test)
    acclist <- append(acclist, sum(test$acc)/nrow(test))
    datlist <- append(datlist, paste(combdf[,k], collapse = ","))
    minlist <- append(minlist,min(test$prob))
    maxlist <- append(maxlist,max(test$prob))
  }
}
proc.time()-ptm

df4 <- data.frame(acc = acclist, info = datlist, minprob = minlist, maxprob = maxlist)
View(df4)


##################################

ggplot(modeldf)+geom_histogram(aes(x=modeldf$Grade), stat = "count")


