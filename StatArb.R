setwd("C:/aya/Documents/MFE/Baruch/Algo Trading")

rm(list = ls())

require(quantmod)
require(PerformanceAnalytics)
require(blotter)
require(FinancialInstrument)
require(quantstrat)
require(forecast)
require(foreach)

tmptz <- Sys.getenv('TZ')
if(tmptz != 'UTC') ttz <- tmptz
Sys.setenv(TZ='UTC')  # set default timezone

RStudio <- TRUE  # RStudio built-in graphics doesn't support dev.new()
if(RStudio)
{   while(dev.cur()[[1]] > 1) dev.off()  # close any open X11 windows
}

#clear portfolio and acct not needed due to the clearing workspace but here incase you don't use it.
suppressWarnings(rm("order_book.pair1",pos=.strategy))
suppressWarnings(rm("account.pairs", "portfolio.pair1", pos=.blotter))
suppressWarnings(rm("initDate", "endDate", "startDate", "initEq", "SD", "N", "symb1", "symb2", 
                    "portfolio1.st", "account.st", "pairStrat", "out1"))

initDate = '2006-01-01'  	
endDate = '2007-12-01'
startDate = '2006-01-02'
initEq = 100000
N = 60

# data <- read.csv(file="jpm_xlf.csv", header=TRUE)
# colnames(data) <- c("Date", "XLF", "JPM")
# 
# jpm.xts <- as.xts(data[,2], order.by=as.Date(data[,1], "%m/%d/%Y"))
# 
# data.returns <- ROC(data.xts)

symb1 <- "JPM"
symb2 <- "XLF"

portfolio1.st <- 'pair1'
account.st <- 'pairs'

####################################################### Get Data #################################################

getSymbols(c(symb1, symb2), from=startDate, to=endDate, adjust=TRUE) 

#Set up currencies
currency("USD")

alignSymbols <- function(symbols, env=.GlobalEnv) {
# natual join those symbols. When joining them, they will cut off those data so that
# they can have the same record length
  if (length(symbols) < 2) 
    stop("Must provide at least 2 symbols")
  if (any(!is.character(symbols))) 
    stop("Symbols must be vector of character strings.")
  ff <- get(symbols[1],env=env)
  for (sym in symbols[-1]) {
    tmp.sym <- get(sym,env=env)
    #the default value of all = FALSE gives a natural join, a special case of an inner 
    #join. Specifying all.x = TRUE gives a left (outer) join, all.y = TRUE a right 
    #(outer) join, and both (all = TRUE a (full) outer join. DBMSes do not match NULL 
    #records, equivalent to incomparables = NA in R.
    ff <- merge(ff,tmp.sym,all=FALSE)
  }
  for (sym in symbols) {
    assign(sym,ff[,grep(sym,colnames(ff))],env=env)
    # grep search for matches to argument pattern within each element of a character vector
    # the sym is the pattern which is a regular expression to be matched in x which is 
    # colnames(ff) in this case
    
    # assign function is to assign the ff[,columns belongs to sym] into sym
  }
  symbols
}

alignSymbols(c(symb1,symb2)) 

stock(symb1, currency="USD", multiplier=1)
# primary_id(in this case symb1):String describing the unique ID for the instrument.
# Most of the wrappers allow this to be a vector.
stock(symb2, currency="USD", multiplier=1)
# stock: creat the financial instrument.

initEq = 10000

########################## Set up portfolio orders and Acct #######################################

#Initialize Portfolio, Account, and Orders
initPortf(name=portfolio1.st, c(symb1,symb2), initDate=initDate)
#Constructs and initializes a portfolio object, which is used to contain transactions, 
#positions, and aggregate level values.

# the second parameter should pass stock into it to initialize the portfolio
initAcct(account.st, portfolios=portfolio1.st, initDate=initDate, initEq=initEq)
initOrders(portfolio=portfolio1.st,initDate=initDate)
# Create initial position limits and levels by symbol
# allow 3 entries for long and short if lvls=3.

MaxPos = 1500  #max position in stockA; 
#max position in stock B will be max * ratio, i.e. no hard position limit in Stock B
lvls = 3  #how many times to fade; Each order's qty will = MaxPos/lvls

# Create initial position limits and levels by symbol
# allow 3 entries for long and short if lvls=3.
addPosLimit(portfolio=portfolio1.st, timestamp=initDate, symbol=symb1, maxpos=MaxPos, longlevels=lvls, minpos=-MaxPos, shortlevels=lvls)
addPosLimit(portfolio=portfolio1.st, timestamp=initDate, symbol=symb2, maxpos=MaxPos, longlevels=lvls, minpos=-MaxPos, shortlevels=lvls)

# position limits: Many strategies will not be allowed to trade unconstrained. Typically, 
#constraints will include position sizing limits.
# addPosLimit("pair1","JPM",timestamp=initDate,maxpos=100, minpos=0)

#position limits
# addPosLimit("pair1","JPM",timestamp=initDate,maxpos=100, minpos=0)

#Set up Strategy
arbstrat<-strategy("pairStrat", mktdata = merge(get(symb1), get(symb2)))

##############################FUNCTIONS#################################

autoregressor1  = function(x){
  
  if(NROW(x)<60){ result = NA} else{
    y = ROC(x$JPM.Close, type="discrete")
    #Calculate the (rate of) change of a series over n periods(default as 1 period)
    y = na.omit(y)
    # will omit the whole line if there is a na value in any column of that line.

    y1 = ROC(x$XLF.Close, type="discrete")
    y1 = na.omit(y1)
    
    lin_reg <-lm(y ~ y1)
    res <- lin_reg$residuals
    
    alpha <- (lin_reg$coefficients)[1]*252
    # intercetion devide by time interval which is 1 in this case and multiply the 252 which
    # gives the one year excess rate of return relative to the other asset
    
#     ar1 <- ar.ols(res, aic = FALSE, order.max=1 )
#     ar_coeff = ar1$ar
#     ar_resids <- ar1$resid

    # I would suggest to use use the linear regression. since there if we want 
    # the arima model to include the intercept then we have to set the 
    # 'include.mean' option to TURE in which case it will make the independence variable minus 
    # their mean (quote from function indication:  Further, if include.mean is true (the default for an ARMA model), this formula applies to X - m rather than X)

    # So I would suggest to use linear regression. 
    #ar1 <- arima(cumsum(res), order=c(1,0,0) )
    X.lm = lm(cumsum(res)[-length(cumsum(res))]~cumsum(res)[-1])
    #b = ar1$coef[1]
    b = X.lm$coef[2]
    #ar_resids <- ar1$residuals
    ar_resids<- X.lm$res
    #a = ar1$coef[2]
    a = X.lm$coef[1]
    rvar <- var(ar_resids)
    kappa <- -log(b)*252
    

    
    
    kappa = -log(X.lm$coef[2])*252
    m = X.lm$coef[1]/(1-X.lm$coef[2])
    rvar <- var(X.lm$res)
    sigma <- sqrt(rvar*2*kappa/(1-X.lm$coef[2]^2))
    sigma_eq <- sqrt(rvar/(1-X.lm$coef[2]^2))
    
    
    cat('k: ', kappa, '\n')
    
    m <- a/(1 - b)
    sigma <- sqrt(rvar*2*kappa/(1-b^2))
    sigma_eq <- sqrt(rvar/(1-b^2))
    
    result <- -1*m/sigma_eq
    cat('s-score : ', result, '\n')
  }
  
  return(result)
}

autoregressor = function(x){
  ans = rollapply(x,N,FUN = autoregressor1,by.column=FALSE)
  return (ans)}
# just a function and there is no N define above
 #by.column: logical. If TRUE, FUN is applied to each column separately
  
########################indicators#############################

arbstrat<-add.indicator(
  strategy  =  arbstrat, 
  name		=	"autoregressor", 
  arguments	=	list(
    x		=	quote(merge(get(symb1), get(symb2)))),
  label		=	"sscore")

################################################ Signals #############################

arbstrat<-add.signal(
  strategy			= arbstrat,
  name				= "sigThreshold",
  arguments			= list(
    threshold		= 1.25,
    column			= "sscore",
    relationship	= "gte",
    cross			= TRUE),
  label				= "Selltime")

arbstrat<-add.signal(
  strategy			= arbstrat,
  name				= "sigThreshold",
  arguments			= list(
    threshold		= 0.1,
    column			= "sscore",
    relationship	= "lt",
    cross			= TRUE),
  label				= "cashtime")

arbstrat<-add.signal(
  strategy  		= arbstrat,
  name				= "sigThreshold",
  arguments			= list(
    threshold		= -0.25,
    column			= "sscore",
    relationship	= "gt",
    cross			= TRUE),
  label				= "cashtime")

arbstrat<-add.signal(
  strategy  		= arbstrat,
  name				= "sigThreshold",
  arguments			= list(
    threshold		= -1.25,
    column			= "sscore",
    relationship	= "lte",
    cross			= TRUE),
  label				= "Buytime")

######################################## Rules #################################################

#Entry Rule Long

# ruleSignal:As described elsewhere in the documentation, quantstrat models orders. 
#This function is the default provided rule function to generate those orders, 
#which will be acted on later as they interact with your market data. 

# column name to chek for signal as before it will generate an column by the add.signal function

arbstrat<- add.rule(arbstrat,
                       name				=	"ruleSignal",
                       arguments			=	list(
                         sigcol			=	"Buytime",
                         sigval			=	TRUE,
                         orderqty		=	100,
                         ordertype		=	"market",
                         orderside		=	"long",
                         pricemethod		=	"market",
                         replace			=	TRUE,
                         TxnFees				=	-1,
                         osFUN				=	osMaxPos), 
                       type				=	"enter",
                       path.dep			=	TRUE,
                       label				=	"Entry")

#Entry Rule Short

arbstrat<- add.rule(arbstrat,
                       name  			=	"ruleSignal",
                       arguments			=	list(
                         sigcol			=	"Selltime",
                         sigval			=	TRUE,
                         orderqty		=	100,
                         ordertype		=	"market",
                         orderside		=	"short",
                         pricemethod		=	"market",
                         replace			=	TRUE,
                         TxnFees				=	-1,
                         osFUN				=	osMaxPos), 
                       type				=	"enter",
                       path.dep			=	TRUE,
                       label				=	"Entry")

#Exit Rules

#Exit 
arbstrat <- add.rule(arbstrat,
                        name				=	"ruleSignal",
                        arguments			=	list(
                          sigcol				=	"cashtime", 
                          sigval			=	TRUE, 
                          orderqty		=	"all", 
                          ordertype		=	"market",
                          orderside		=	"long", 
                          pricemethod		=	"market",
                          replace			=	TRUE,
                          TxnFees			=	-1),
                        type			=	"exit",
                        path.dep			=	TRUE,
                        label				=	"Exit")

##############################    Apply Strategy ##############################################

out <- applyStrategy(strategy=arbstrat, portfolios=portfolio1.st)
updatePortf(Portfolio=portfolio1.st,Dates=paste("::",as.Date(Sys.time()),sep=''))
updateAcct(account.st,Dates=paste(startDate,endDate,sep="::")) 
updateEndEq(account.st,Dates=paste(startDate,endDate,sep="::"))
getEndEq(account.st,Sys.time())


############################# Portfolio Return Characterics ################################
#get portfolio data
portRet <- PortfReturns(account.st)
portRet$Total <- rowSums(portRet, na.rm=TRUE)
charts.PerformanceSummary(portRet$Total)
chart.Posn(portfolio1.st,"JPM")
results1<-getTxns(portfolio1.st,"JPM")
#plot(results1$Net.Txn.Realized.PL)
