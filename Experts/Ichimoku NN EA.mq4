//+------------------------------------------------------------------+
//|                                                      Ichimoku EA |
//|                                           Copyright 2017, Shk0da |
//|                                    https://github.com/Shk0da/mt4 |
//+------------------------------------------------------------------+
#include <stdlib.mqh>
#include <stderror.mqh> 
#property copyright ""
#property link ""

// ------------------------------------------------------------------------------------------------
// EXTERNAL VARIABLES
// ------------------------------------------------------------------------------------------------

extern int magic=19274;
int magic_lock=777;
// Configuration
extern string CommonSettings="---------------------------------------------";
extern int user_slippage=2;
extern int user_tp=200;
extern int user_sl=100;
extern bool use_basic_tp=true;
extern bool use_basic_sl=true;
extern bool use_dynamic_tp=false;
extern bool use_dynamic_sl=false;
extern string MoneyManagementSettings="---------------------------------------------";
// Money Management
extern double min_lots=0.01;
extern int risk=33;
extern int martin_aver_k=2;
extern double balance_limit=50;
extern int max_orders=1;
extern int surfing=0;
extern bool close_loss_orders=true;
extern bool global_basket=true;
extern bool safety=false;
extern bool use_reverse_orders=false;
extern bool turbo_mode=true;
extern double max_spread=30.0;
extern bool use_nn=true;
extern string nn_url="http://localhost/api";
// Trailing stop
extern string TrailingStopSettings="---------------------------------------------";
extern bool ts_enable=true;
extern int ts_val=19;
extern int ts_step=4;
extern bool ts_only_profit=true;
// Optimization
extern string Optimization="---------------------------------------------";
// Indicators
extern int shift=1;
extern int atr_period=14;
extern int atr_tpk=1;
extern int atr_slk=1;
extern int x1 = 5;
extern int x2 = 7;
extern int x3 = 33;
extern int x4 = 70;
extern int x5 = 70;
extern int x6 = 60;
extern int x7 = 40;
// ------------------------------------------------------------------------------------------------
// GLOBAL VARIABLES
// ------------------------------------------------------------------------------------------------

string key="Ichimoku EA: ";
int DAY=86400;
int order_ticket;
double order_lots;
double order_price;
double order_profit;
double order_sl;
double order_tp;
int order_magic;
int order_time;
int orders=0;
int direction=0;
double max_profit=0;
double close_profit=0;
double last_order_profit=0;
double last_order_lots=0;
double last_order_price=0;
double last_close_price=0;
color c=Black;
double balance;
double equity;
int slippage=0;
// OrderReliable
int retry_attempts= 10;
double sleep_time = 4.0;
double sleep_maximum=25.0;  // in seconds
string OrderReliable_Fname="OrderReliable fname unset";
static int _OR_err=0;
string OrderReliableVersion="V1_1_1";
// ------------------------------------------------------------------------------------------------
// START
// ------------------------------------------------------------------------------------------------
int start()
  {

   if(FileIsExist("Ichimoku EA.tpl"))
     {
      ChartApplyTemplate(0,"\\Templates\\Ichimoku EA.tpl");
     }

   if(AccountBalance()<=balance_limit)
     {
      Alert("Balance: "+AccountBalance());
      return(0);
     }

   if(MarketInfo(Symbol(),MODE_DIGITS)==4)
     {
      slippage=user_slippage;
     }
   else if(MarketInfo(Symbol(),MODE_DIGITS)==5)
     {
      slippage=10*user_slippage;
     }

   if(IsTradeAllowed()==false)
     {
      Comment("Trade not allowed.");
      return(0);
     }

   Comment("\nIchimoku EA is running.");

   return(0);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(use_nn)
     {
      string json=StringConcatenate("{",
                                    "\"datetime\"",
                                    ":",
                                    "\"",
                                    TimeCurrent()*1000,
                                    "\"",
                                    ",",
                                    "\"symbol\"",
                                    ":",
                                    "\"",
                                    Symbol(),
                                    "\"",
                                    ",",
                                    "\"timeFrame\"",
                                    ":",
                                    "\"",
                                    Period(),
                                    "\"",
                                    ",",
                                    "\"open\"",
                                    ":",
                                    "\"",
                                    iOpen(Symbol(),0,0),
                                    "\"",
                                    ",",
                                    "\"max\"",
                                    ":",
                                    iHigh(Symbol(),0,0),
                                    ",",
                                    "\"min\"",
                                    ":",
                                    iLow(Symbol(),0,0),
                                    ",",
                                    "\"close\"",
                                    ":",
                                    iClose(Symbol(),0,0),
                                    ",",
                                    "\"value\"",
                                    ":",
                                    iVolume(Symbol(),0,0),
                                    "}"
                                    );

      char post_data[];
      StringToCharArray(json,post_data,0,StringLen(json));
      char results[];
      string result_header;
      ResetLastError();
      int result= WebRequest("POST",nn_url+"/add-tick","Content-Type: application/json\r\n",5000,post_data,results,result_header);
      if(result == -1) Print("Error in WebRequest. Error code: ",GetLastError());

     }
   InicializarVariables();
   ActualizarOrdenes();
   Trade();
  }
//+------------------------------------------------------------------+
//| Суммарный профит открытых позиций                                |
//+------------------------------------------------------------------+
double GetPfofit()
  {
   double profit=0;
   int i;

   for(i=0; i<OrdersTotal(); i++)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
        {
         if(global_basket)
           {
            if((OrderMagicNumber()==magic || OrderMagicNumber()==magic+magic_lock) && (OrderType()==OP_BUY || OrderType()==OP_SELL))
              {
               profit+=OrderProfit()+OrderSwap()-OrderCommission();
              }
           }
         else
           {
            if(OrderSymbol()==Symbol() && (OrderMagicNumber()==magic || OrderMagicNumber()==magic+magic_lock) && (OrderType()==OP_BUY || OrderType()==OP_SELL))
              {
               profit+=OrderProfit()+OrderSwap()-OrderCommission();
              }
           }
        }
     }
   return(profit);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void TrailingStop()
  {
   for(int i=0; i<OrdersTotal(); i++)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
        {
         if(OrderSymbol()==Symbol() && (OrderMagicNumber()==magic || OrderMagicNumber()==magic+magic_lock))
           {
            TrailingPositions();
           }
        }
     }
  }
//+------------------------------------------------------------------+
//| Position maintenance simple trawl                             |
//+------------------------------------------------------------------+
void TrailingPositions()
  {
   double pBid,pAsk,pp;
//----
   pp=MarketInfo(OrderSymbol(),MODE_POINT);

   double val;
   int stop_level=MarketInfo(Symbol(),MODE_STOPLEVEL)+MarketInfo(Symbol(),MODE_SPREAD);
   if(use_dynamic_sl==1)
     {
      double atr=iATR(Symbol(),0,atr_period,shift)/0.00001;
      if(atr<stop_level) atr=stop_level;
      val=atr;
        } else {
      if(ts_val<stop_level) ts_val=stop_level;
      val=ts_val;
     }

   if(OrderType()==OP_BUY)
     {
      pBid=MarketInfo(OrderSymbol(),MODE_BID);
      if(!ts_only_profit || (pBid-OrderOpenPrice())>val*pp)
        {
         if(OrderStopLoss()<pBid-(val+ts_step-1)*pp)
           {
            ModifyStopLoss(pBid-val*pp);
            return;
           }
        }
     }
   if(OrderType()==OP_SELL)
     {
      pAsk=MarketInfo(OrderSymbol(),MODE_ASK);
      if(!ts_only_profit || OrderOpenPrice()-pAsk>val*pp)
        {
         if(OrderStopLoss()>pAsk+(val+ts_step-1)*pp || OrderStopLoss()==0)
           {
            ModifyStopLoss(pAsk+val*pp);
            return;
           }
        }
     }
  }
//+------------------------------------------------------------------+
//| The transfer of the StopLoss level                                          |
//| Settings:                                                       |
//|   ldStopLoss - level StopLoss                                  |
//+------------------------------------------------------------------+
void ModifyStopLoss(double ldStopLoss)
  {
   double ldTakeProfit=ts_only_profit
                       ? OrderTakeProfit()+ts_step*MarketInfo(OrderSymbol(),MODE_POINT)*((OrderType()==OP_BUY) ? 1 : -1)
                       : OrderTakeProfit();
   OrderModify(OrderTicket(),OrderOpenPrice(),ldStopLoss,ldTakeProfit,0,CLR_NONE);
  }
//+------------------------------------------------------------------+

// ------------------------------------------------------------------------------------------------
// INITIALIZE VARIABLES
// ------------------------------------------------------------------------------------------------
void InicializarVariables()
  {
   orders=0;
   direction=0;
   order_ticket=0;
   order_lots=0;
   order_price= 0;
   order_time = 0;
   order_profit=0;
   order_sl=0;
   order_tp=0;
   order_magic=0;
   last_order_profit=0;
   last_order_lots=0;
  }
// ------------------------------------------------------------------------------------------------
// ACTUALIZAR ORDENES
// ------------------------------------------------------------------------------------------------
void ActualizarOrdenes()
  {
   int ordenes=0;
   bool encontrada;

   for(int i=0; i<OrdersTotal(); i++)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
        {
         if(((!global_basket && OrderSymbol()==Symbol()) || global_basket) && (OrderMagicNumber()==magic || OrderMagicNumber()==magic+magic_lock) && (OrderType()==OP_BUY || OrderType()==OP_SELL))
           {
            ordenes++;
           }

         if(OrderSymbol()==Symbol() && (OrderMagicNumber()==magic || OrderMagicNumber()==magic+magic_lock) && (OrderType()==OP_BUY || OrderType()==OP_SELL))
           {
            order_ticket=OrderTicket();
            order_lots=OrderLots();
            order_price= OrderOpenPrice();
            order_time = OrderOpenTime();
            order_profit=OrderProfit();
            order_sl=OrderStopLoss();
            order_tp=OrderTakeProfit();
            order_magic=OrderMagicNumber();

            if(OrderType()==OP_BUY) direction=1;
            if(OrderType()==OP_SELL) direction=2;
           }
        }
     }
   orders=ordenes;

   if(OrdersHistoryTotal()>0)
     {
      i=1;
      while(i<=100 && encontrada==FALSE)
        {
         int n=OrdersHistoryTotal()-i;
         if(OrderSelect(n,SELECT_BY_POS,MODE_HISTORY) && (OrderMagicNumber()==magic || OrderMagicNumber()==magic+magic_lock))
           {
            last_order_profit=OrderProfit();
            last_order_lots=OrderLots();
            last_order_price=OrderOpenPrice();
            last_close_price=OrderClosePrice();
           }
         i++;
        }
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetMaxLot(int Risk)
  {
   double Free=AccountFreeMargin();
   double margin=MarketInfo(Symbol(),MODE_MARGINREQUIRED);
   double Step= MarketInfo(Symbol(),MODE_LOTSTEP);
   double Lot = MathFloor(Free*Risk/100/margin/Step)*Step;
   if(Lot*margin>Free) return(0);
   return(Lot);
  }
// ------------------------------------------------------------------------------------------------
// CALCULATE VOLUME
// ------------------------------------------------------------------------------------------------
double CalcularVolumen()
  {
   int n;
   double aux;

   aux=risk*AccountFreeMargin();
   aux=aux/100000;
   n=MathFloor(aux/min_lots);
   aux=n*min_lots;

   if(surfing>0)
     {
      aux=last_order_lots+min_lots;
      if(aux>surfing*MarketInfo(Symbol(),MODE_LOTSTEP)) aux=min_lots;
     }

   double max=GetMaxLot(risk);
   if(aux>max) aux=max;
   if(aux<min_lots) aux=min_lots;

   if(last_order_profit<0)
     {
      aux=last_order_lots*martin_aver_k;
      last_order_profit=0;
     }

   if(aux>MarketInfo(Symbol(),MODE_MAXLOT)) aux=MarketInfo(Symbol(),MODE_MAXLOT);
   if(aux<MarketInfo(Symbol(),MODE_MINLOT)) aux=MarketInfo(Symbol(),MODE_MINLOT);

   return(aux);
  }
// ------------------------------------------------------------------------------------------------
// CALCULATED TAKE PROFIT
// ------------------------------------------------------------------------------------------------
double GetTakeProfit(int op)
  {
   if(use_basic_tp == 0) return(0);

   double aux_take_profit=0;
   double spread=MarketInfo(Symbol(),MODE_ASK)-MarketInfo(Symbol(),MODE_BID);
   double val;

   int stop_level=MarketInfo(Symbol(),MODE_STOPLEVEL)+MarketInfo(Symbol(),MODE_SPREAD);
   if(use_dynamic_tp==1)
     {
      double atr=iATR(Symbol(),0,atr_period,shift)/0.00001*(MarketInfo(Symbol(),MODE_DIGITS)>=4 ? 1 : .5)*atr_tpk;
      if(atr<stop_level) atr=stop_level;
      val=atr*MarketInfo(Symbol(),MODE_POINT);
        } else {
      if(user_tp<stop_level) user_tp=stop_level;
      val=user_tp*MarketInfo(Symbol(),MODE_POINT);
     }

   if(op==OP_BUY)
     {
      aux_take_profit=MarketInfo(Symbol(),MODE_ASK)+spread+val;
     }
   else if(op==OP_SELL) 
     {
      aux_take_profit=MarketInfo(Symbol(),MODE_BID)-spread-val;
     }

   return(aux_take_profit);
  }
// ------------------------------------------------------------------------------------------------
// CALCULATES STOP LOSS
// ------------------------------------------------------------------------------------------------
double GetStopLoss(int op)
  {
   if(use_basic_sl == 0) return(0);

   double aux_stop_loss=0;

   double val;
   int stop_level=MarketInfo(Symbol(),MODE_STOPLEVEL)+MarketInfo(Symbol(),MODE_SPREAD);
   if(use_dynamic_sl==1)
     {
      double atr=iATR(Symbol(),0,atr_period,shift)/0.00001*(MarketInfo(Symbol(),MODE_DIGITS)>=4 ? 2 : 1)*atr_slk;
      if(atr<stop_level) atr=stop_level;
      val=atr*MarketInfo(Symbol(),MODE_POINT);
        } else {
      if(user_sl<stop_level) user_sl=stop_level;
      val=user_sl*MarketInfo(Symbol(),MODE_POINT);
     }

   if(op==OP_BUY)
     {
      aux_stop_loss=MarketInfo(Symbol(),MODE_ASK)-val;
     }
   else if(op==OP_SELL)
     {
      aux_stop_loss=MarketInfo(Symbol(),MODE_BID)+val;
     }

   return(aux_stop_loss);
  }

int UpTo30Counter=0;
double Array_spread[30];
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnInit()
  {
   ArrayInitialize(Array_spread,0);
  }

// ------------------------------------------------------------------------------------------------
// CALCULATED SIGNAL 
// ------------------------------------------------------------------------------------------------
double scalp1 = 0;
double scalp2 = 0;
double fisher1 = 0;
double fisher2 = 0;
double xps1 = 0;
double xps2 = 0;
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double CalculaSignal()
  {
   if(AccountBalance()<=balance_limit)
     {
      return(0);
     }

   int aux=0;
   int aux_tenkan_sen=9;
   double aux_kijun_sen=26;
   double aux_senkou_span=52;
   int aux_shift=shift;
   double kt1=0,kb1=0,kt2=0,kb2=0;
   double ts1,ts2,ks1,ks2,ssA1,ssA2,ssB1,ssB2,close1,close2;

   ts1 = iIchimoku(Symbol(), PERIOD_H1, aux_tenkan_sen, aux_kijun_sen, aux_senkou_span, MODE_TENKANSEN, aux_shift);
   ks1 = iIchimoku(Symbol(), PERIOD_H1, aux_tenkan_sen, aux_kijun_sen, aux_senkou_span, MODE_KIJUNSEN, aux_shift);
   ssA1 = iIchimoku(Symbol(), PERIOD_H1, aux_tenkan_sen, aux_kijun_sen, aux_senkou_span, MODE_SENKOUSPANA, aux_shift);
   ssB1 = iIchimoku(Symbol(), PERIOD_H1, aux_tenkan_sen, aux_kijun_sen, aux_senkou_span, MODE_SENKOUSPANB, aux_shift);
   close1=iClose(Symbol(),PERIOD_H1,aux_shift);

   ts2 = iIchimoku(Symbol(), PERIOD_H1, aux_tenkan_sen, aux_kijun_sen, aux_senkou_span, MODE_TENKANSEN, aux_shift+1);
   ks2 = iIchimoku(Symbol(), PERIOD_H1, aux_tenkan_sen, aux_kijun_sen, aux_senkou_span, MODE_KIJUNSEN, aux_shift+1);
   ssA2 = iIchimoku(Symbol(), PERIOD_H1, aux_tenkan_sen, aux_kijun_sen, aux_senkou_span, MODE_SENKOUSPANA, aux_shift+1);
   ssB2 = iIchimoku(Symbol(), PERIOD_H1, aux_tenkan_sen, aux_kijun_sen, aux_senkou_span, MODE_SENKOUSPANB, aux_shift+1);
   close2=iClose(Symbol(),PERIOD_H1,aux_shift+1);

   if(ssA1 >= ssB1) kt1 = ssA1;
   else kt1 = ssB1;

   if(ssA1 <= ssB1) kb1 = ssA1;
   else kb1 = ssB1;

   if(ssA2 >= ssB2) kt2 = ssA2;
   else kt2 = ssB2;

   if(ssA2 <= ssB2) kb2 = ssA2;
   else kb2 = ssB2;

   if((ts1>ks1 && ts2<ks2 && ks1>kt1) || (close1>ks1 && close2<ks2 && ks1>kt1) || (close1>kt1 && close2<kt2))
     {
      aux=1;
     }

   if((ts1<ks1 && ts2>ks2 && ts1<kb1) || (close1<ks1 && close2>ks2 && ks1<kb1) || (close1<kb1 && close2>kb2))
     {
      aux=2;
     }

   int rsi_period=14;
   int macd_signal_period1=12;
   int macd_signal_period2=26;
   int macd_signal_period3=9;

   int osma_fast_ema=12;
   int osma_slow_ema=26;
   int osma_signal_sma=9;

   double rsi=iRSI(Symbol(),0,14,PRICE_CLOSE,aux_shift);
   double macd1 = iMACD(Symbol(), PERIOD_M5, macd_signal_period1, macd_signal_period2, macd_signal_period3, PRICE_CLOSE, MODE_SIGNAL, aux_shift);
   double macd2 = iMACD(Symbol(), PERIOD_M5, macd_signal_period1, macd_signal_period2, macd_signal_period3, PRICE_CLOSE, MODE_SIGNAL, aux_shift+2);
   double osma=iOsMA(Symbol(),PERIOD_H1,osma_fast_ema,osma_slow_ema,osma_signal_sma,PRICE_CLOSE,aux_shift);

   int aux1=0;
   if(aux==1 && osma>0 && rsi>=40 && macd1<macd2) aux1=1;
   else if(aux==2 && osma<0 && rsi<=60 && macd1>macd2) aux1=-1;

   int kg=2;
   int Slow_MACD= 18;
   int Alfa_min = 2;
   int Alfa_delta= 34;
   int Fast_MACD = 1;

   int j=0;
   int r=60/Period();
   double MA_0=iMA(Symbol(),0,Slow_MACD*r*kg,0,MODE_SMA,PRICE_OPEN,j);
   double MA_1=iMA(Symbol(),0,Slow_MACD*r*kg,0,MODE_SMA,PRICE_OPEN,j+1);
   double Alfa=((MA_0-MA_1)/MarketInfo(Symbol(),MODE_POINT))*r;
   double Fast_0=iOsMA(Symbol(),0,Fast_MACD*r,Slow_MACD*r,Slow_MACD*r,PRICE_OPEN,j);
   double Fast_1=iOsMA(Symbol(),0,Fast_MACD*r,Slow_MACD*r,Slow_MACD*r,PRICE_OPEN,j+1);
   double Slow_0=iOsMA(Symbol(),0,(Fast_MACD+slippage)*r,Slow_MACD*r,Slow_MACD*r,PRICE_OPEN,j);
   double Slow_1=iOsMA(Symbol(),0,(Fast_MACD+slippage)*r,Slow_MACD*r,Slow_MACD*r,PRICE_OPEN,j+1);

   bool trend_up=0;
   bool trend_dn=0;
   if(Alfa> Alfa_min && Alfa< (Alfa_min+Alfa_delta)) trend_up=1;
   if(Alfa<-Alfa_min && Alfa>-(Alfa_min+Alfa_delta)) trend_dn=1;
   bool longsignal=0;
   bool shortsignal=0;
   if((Fast_0-Slow_0)>0.0 && (Fast_1-Slow_1)<=0.0) longsignal=1;
   if((Fast_0-Slow_0)<0.0 && (Fast_1-Slow_1)>=0.0) shortsignal=1;

   int aux2=0;
   int aux3=aux3();
   if((((trend_up || longsignal) && aux3>0) || aux3>1) && rsi>70) aux2=1;
   else if((((trend_dn || shortsignal) && aux3<0) || aux3<-1) && rsi<30) aux2=-1;

   int aux4=0;
   scalp1=iCustom(Symbol(),0,"Scalp",200,400,0,12,16711680,0,0,0,2,65535,0,2,0,2,255,0,2,-0.500000,0.500000,0,1);
   if(scalp1>scalp2 && scalp1>0 && scalp2<0) aux4 = 1;
   if(scalp1<scalp2 && scalp1<0 && scalp2>0) aux4 = -1;
   scalp2=scalp1;

   int aux5=0;
   fisher1=iCustom(Symbol(),0,"Fisher",200,0,2,255,0,2,0,2,65280,0,2,0,2,255,0,3,12632256,2,1,-0.2500,0.2500,0,1);
   if(fisher1 > 0 && fisher2 < fisher1 && fisher2 < 0) aux5 = 1;
   if(fisher1 < 0 && fisher1 < fisher2 && fisher2 > 0) aux5 = -1;
   fisher2=fisher1;

   strength=GetStrengthTrend();

   double bid = MarketInfo(Symbol(),MODE_BID);
   double ask = MarketInfo(Symbol(),MODE_ASK);

   int nn_predict = 0;
   if(use_nn)
     {
      ResetLastError();
      string headers;
      char results[],body[];
      int result= WebRequest("GET",nn_url+"/prediction?symbol="+Symbol()+Period(),"Content-Type: application/json\r\n",5000,body,results,headers);
      if(result == -1) Print("Error in WebRequest. Error code: ",GetLastError());
      double predict=StrToDouble(CharArrayToString(results));
      double spread=ask-bid;
      
      if(predict>0 && predict > ask+spread) nn_predict = 1;
      if(predict>0 && predict < bid-spread) nn_predict = -1;
     }

   if(turbo_mode)
     {
      ArrayCopy(Array_spread,Array_spread,0,1,29);
      Array_spread[29]=ask-bid;
      if(UpTo30Counter<30) UpTo30Counter++;

      double sumofspreads=0;
      int loopcount2=29;
      for(int loopcount1=0; loopcount1<UpTo30Counter; loopcount1++)
        {
         sumofspreads+=Array_spread[loopcount2];
         loopcount2--;
        }

      double avgspread=sumofspreads/UpTo30Counter;
      if(NormalizeDouble(avgspread,Digits)<NormalizeDouble(max_spread*Point,Digits))
        {
         double res=(aux1+aux2+aux4+aux5);
         double imalow=iMA(Symbol(),0,3,0,MODE_LWMA,PRICE_LOW,0);
         double imahigh=iMA(Symbol(),0,3,0,MODE_LWMA,PRICE_HIGH,0);

         double ibandslower = iBands(Symbol(), 0, 3, 2.0, 0, PRICE_OPEN, MODE_LOWER, 0);
         double ibandsupper = iBands(Symbol(), 0, 3, 2.2, 0, PRICE_OPEN, MODE_UPPER, 0);

         double envelopeslower = iEnvelopes(Symbol(), 0, 3, MODE_LWMA, 0, PRICE_OPEN, 0.07, MODE_LOWER, 0);
         double envelopesupper = iEnvelopes(Symbol(), 0, 3, MODE_LWMA, 0, PRICE_OPEN, 0.07, MODE_UPPER, 0);

         int h=0;
         if(bid<imalow) h++;
         if(bid<ibandslower) h++;
         if(bid<envelopeslower) h++;

         int l=0;
         if(ask>imahigh) l--;
         if(ask>ibandsupper) l--;
         if(ask>envelopesupper) l--;

         if((((h>1 && res>0) || h>2)  && nn_predict>=0) || (((l<-1 && res<0) || l<-2) && nn_predict<=0)) return(strength + h + l + res);
        }
     }

   int aux6=0;
   if((fisher1 > scalp2 && scalp2 < 0 && fisher1 > 0) || (scalp1 > fisher2 && fisher2 < 0 && scalp1 > 0)) aux6 = 1;
   if((fisher1 < scalp2 && fisher1 < 0 && scalp2 > 0) || (scalp1 < fisher2 && scalp1 < 0 && fisher2 > 0)) aux6 = -1;

   int aux7=0;
   if(scalp2>0 && fisher1>0.25) aux7=1;
   if(scalp2<0 && fisher1<-0.25) aux7=-1;

   int aux8=0;
   if(rsi<=35) aux8=1;
   if(rsi>=65) aux8=-1;

   int aux82=0;
   if(rsi<46) aux82=1;
   if(rsi>54) aux82=-1;

   int aux9=0;
   int aux9count=(aux4+aux5+aux6+aux7);
   if(aux6 > 0 && rsi>50) aux9=1;
   if(aux6 < 0 && rsi<50) aux9=1;

   int aux10=0;
   double xl1 = iHighest(Symbol(), 0, 0);
   double xl2 = iHighest(Symbol(), 0, 1);
   double xl3 = iHighest(Symbol(), 0, 2);
   double xls1 = iLowest(Symbol(), 0, 0);
   double xls2 = iLowest(Symbol(), 0, 1);
   double xls3 = iLowest(Symbol(), 0, 2);
   double xls1a = iClose(Symbol(), 0, 0);
   double xls2a = iClose(Symbol(), 0, 1);
   double xls3a = iClose(Symbol(), 0, 2);

   if(xl3 < xl2 < xl1 && xls3a < xls2a < xls1a) aux10=1;
   if(xls3> xls2> xls1 && xls3a> xls2a > xls1a) aux10=-1;

   int aux11=0;
   xps1=iCustom(Symbol(),PERIOD_M5,"XPS",200,false,16776960,16711935,1,0,12,4294967295,0,0,0,2,65280,0,4,0,2,255,0,4,12632256,2,1,0.00000000,0,1);
   if(xps1 > 0 && xps2 < xps1 && xps2 < 0 && xps1 < 0.5 && rsi < 45) aux11 = 1;
   if(xps1 < 0 && xps1 < xps2 && xps2 > 0 && xps1> -0.5 && rsi > 55) aux11 = -1;
   xps2=xps1;

   int aux12=0;
   double repulseIndex7[4];
   double repulseIndex12[4];
   double repulseIndex13[4];
   for(int i=1;i<=3;i++)
     {
      repulseIndex7[i]=iMA(Symbol(),0,7,0,MODE_EMA,PRICE_CLOSE,i);
      repulseIndex12[i] = iMA(Symbol(),0,12,0,MODE_EMA,PRICE_MEDIAN,i);
      repulseIndex13[i] = iMA(Symbol(),0,13,0,MODE_EMA,PRICE_MEDIAN,i);
     }

   int vadoLong12=((repulseIndex12[2]<repulseIndex12[3]) && (repulseIndex12[2]<repulseIndex12[1])) ? 1 : 0;
   int vadoShort12=((repulseIndex12[2]>repulseIndex12[3]) && (repulseIndex12[2]>repulseIndex12[1])) ? -1 : 0;
   int vadoLong13=((repulseIndex13[2]<repulseIndex13[3]) && (repulseIndex13[2]<repulseIndex13[1])) ? 1 : 0;
   int vadoShort13=((repulseIndex13[2]>repulseIndex13[3]) && (repulseIndex13[2]>repulseIndex13[1])) ? -1 : 0;
   int vadoLong7=((repulseIndex7[2]>repulseIndex7[3]) && (repulseIndex7[2]<repulseIndex7[1])) ? 1 : 0;
   int vadoShort7=((repulseIndex7[2]<repulseIndex7[3]) && (repulseIndex7[2]>repulseIndex7[1])) ? -1 : 0;

   if((vadoLong12+vadoLong13+vadoLong7)>1 && rsi<40) aux12=1;
   if((vadoShort12+vadoShort13+vadoShort7)<-1 && rsi>60) aux12=-1;

   double sig2=(aux11+aux12);
   double sig=(aux1+aux2+aux9+aux10);

   sig2=sig2>0 ? 1 :(sig2<0 ? -1 : 0);
   sig=sig>0 ? 1 :(sig<0 ? -1 : 0);

   double sig3=0;
   double calcsig3=(aux2+aux9+aux10+aux11+aux12+strength)*100/x1;
   if(calcsig3>x3) sig3=1;
   if(calcsig3<-x3) sig3=-1;
   sig3=((sig3>0 && (osma>0 || strength>0 && rsi>x6)) || (sig3<0 && (osma<0 || strength<0 && rsi<x7))) ? sig3 : 0;
   if(calcsig3 >= x4) sig3 = 2;
   if(calcsig3 <= -x4) sig3 = -2;

   double fkf89=(sig+sig2+sig3+aux8+aux82+strength)*100/x2;
   if(fkf89>=x5 && rsi>x6 && nn_predict >= 0) return(2);
   if(fkf89<=-x5 && rsi<x7 && nn_predict <= 0) return(-2);
   sig=(sig>0 && sig3>0) ? 1 :(sig<0 && sig3<0) ? -1 : 0;
   sig2=(sig2>0 && sig3>0) ? 1 :(sig2<0 && sig3<0) ? -1 : 0;

   sig2=((sig2>0 && aux82>0) || (sig2<0 && aux82<0)) ? sig2 : 0;
   sig=((sig>0 && aux8>0 && strength>0 && osma>0) || (sig<0 && aux8<0 && strength<0 && osma<0)) ? sig : 0;

   double signal = (sig+sig2);
   return((signal > 0 && nn_predict >= 0) || (signal < 0 && nn_predict <= 0) ? signal : nn_predict);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int aux3()
  {
   int     TimeFrame1     = 15;
   int     TimeFrame2     = 60;
   int     TimeFrame3     = 240;
   int     TrendPeriod1   = 5;
   int     TrendPeriod2   = 8;
   int     TrendPeriod3   = 13;
   int     TrendPeriod4   = 21;
   int     TrendPeriod5   = 34;

   double MaH11v,MaH41v,MaD11v,MaH1pr1v,MaH4pr1v,MaD1pr1v;
   double MaH12v,MaH42v,MaD12v,MaH1pr2v,MaH4pr2v,MaD1pr2v;
   double MaH13v,MaH43v,MaD13v,MaH1pr3v,MaH4pr3v,MaD1pr3v;
   double MaH14v,MaH44v,MaD14v,MaH1pr4v,MaH4pr4v,MaD1pr4v;
   double MaH15v,MaH45v,MaD15v,MaH1pr5v,MaH4pr5v,MaD1pr5v;

   double u1x5v,u1x8v,u1x13v,u1x21v,u1x34v;
   double u2x5v,u2x8v,u2x13v,u2x21v,u2x34v;
   double u3x5v,u3x8v,u3x13v,u3x21v,u3x34v;
   double u1acv,u2acv,u3acv;

   double d1x5v,d1x8v,d1x13v,d1x21v,d1x34v;
   double d2x5v,d2x8v,d2x13v,d2x21v,d2x34v;
   double d3x5v,d3x8v,d3x13v,d3x21v,d3x34v;
   double d1acv,d2acv,d3acv;

   MaH11v=iMA(NULL,TimeFrame1,TrendPeriod1,0,MODE_SMA,PRICE_CLOSE,0);   MaH1pr1v=iMA(NULL,TimeFrame1,TrendPeriod1,0,MODE_SMA,PRICE_CLOSE,1);
   MaH12v=iMA(NULL,TimeFrame1,TrendPeriod2,0,MODE_SMA,PRICE_CLOSE,0);   MaH1pr2v=iMA(NULL,TimeFrame1,TrendPeriod2,0,MODE_SMA,PRICE_CLOSE,1);
   MaH13v=iMA(NULL,TimeFrame1,TrendPeriod3,0,MODE_SMA,PRICE_CLOSE,0);   MaH1pr3v=iMA(NULL,TimeFrame1,TrendPeriod3,0,MODE_SMA,PRICE_CLOSE,1);
   MaH14v=iMA(NULL,TimeFrame1,TrendPeriod4,0,MODE_SMA,PRICE_CLOSE,0);   MaH1pr4v=iMA(NULL,TimeFrame1,TrendPeriod4,0,MODE_SMA,PRICE_CLOSE,1);
   MaH15v=iMA(NULL,TimeFrame1,TrendPeriod5,0,MODE_SMA,PRICE_CLOSE,0);   MaH1pr5v=iMA(NULL,TimeFrame1,TrendPeriod5,0,MODE_SMA,PRICE_CLOSE,1);

   MaH41v=iMA(NULL,TimeFrame2,TrendPeriod1,0,MODE_SMA,PRICE_CLOSE,0);   MaH4pr1v=iMA(NULL,TimeFrame2,TrendPeriod1,0,MODE_SMA,PRICE_CLOSE,1);
   MaH42v=iMA(NULL,TimeFrame2,TrendPeriod2,0,MODE_SMA,PRICE_CLOSE,0);   MaH4pr2v=iMA(NULL,TimeFrame2,TrendPeriod2,0,MODE_SMA,PRICE_CLOSE,1);
   MaH43v=iMA(NULL,TimeFrame2,TrendPeriod3,0,MODE_SMA,PRICE_CLOSE,0);   MaH4pr3v=iMA(NULL,TimeFrame2,TrendPeriod3,0,MODE_SMA,PRICE_CLOSE,1);
   MaH44v=iMA(NULL,TimeFrame2,TrendPeriod4,0,MODE_SMA,PRICE_CLOSE,0);   MaH4pr4v=iMA(NULL,TimeFrame2,TrendPeriod4,0,MODE_SMA,PRICE_CLOSE,1);
   MaH45v=iMA(NULL,TimeFrame2,TrendPeriod5,0,MODE_SMA,PRICE_CLOSE,0);   MaH4pr5v=iMA(NULL,TimeFrame2,TrendPeriod5,0,MODE_SMA,PRICE_CLOSE,1);

   MaD11v=iMA(NULL,TimeFrame3,TrendPeriod1,0,MODE_SMA,PRICE_CLOSE,0);   MaD1pr1v=iMA(NULL,TimeFrame3,TrendPeriod1,0,MODE_SMA,PRICE_CLOSE,1);
   MaD12v=iMA(NULL,TimeFrame3,TrendPeriod2,0,MODE_SMA,PRICE_CLOSE,0);   MaD1pr2v=iMA(NULL,TimeFrame3,TrendPeriod2,0,MODE_SMA,PRICE_CLOSE,1);
   MaD13v=iMA(NULL,TimeFrame3,TrendPeriod3,0,MODE_SMA,PRICE_CLOSE,0);   MaD1pr3v=iMA(NULL,TimeFrame3,TrendPeriod3,0,MODE_SMA,PRICE_CLOSE,1);
   MaD14v=iMA(NULL,TimeFrame3,TrendPeriod4,0,MODE_SMA,PRICE_CLOSE,0);   MaD1pr4v=iMA(NULL,TimeFrame3,TrendPeriod4,0,MODE_SMA,PRICE_CLOSE,1);
   MaD15v=iMA(NULL,TimeFrame3,TrendPeriod5,0,MODE_SMA,PRICE_CLOSE,0);   MaD1pr5v=iMA(NULL,TimeFrame3,TrendPeriod5,0,MODE_SMA,PRICE_CLOSE,1);

   if(MaH11v < MaH1pr1v) {u1x5v = 0; d1x5v = 1;}
   if(MaH11v > MaH1pr1v) {u1x5v = 1; d1x5v = 0;}
   if(MaH11v == MaH1pr1v){u1x5v = 0; d1x5v = 0;}
   if(MaH41v < MaH4pr1v) {u2x5v = 0; d2x5v = 1;}
   if(MaH41v > MaH4pr1v) {u2x5v = 1; d2x5v = 0;}
   if(MaH41v == MaH4pr1v){u2x5v = 0; d2x5v = 0;}
   if(MaD11v < MaD1pr1v) {u3x5v = 0; d3x5v = 1;}
   if(MaD11v > MaD1pr1v) {u3x5v = 1; d3x5v = 0;}
   if(MaD11v == MaD1pr1v){u3x5v = 0; d3x5v = 0;}

   if(MaH12v < MaH1pr2v) {u1x8v = 0; d1x8v = 1;}
   if(MaH12v > MaH1pr2v) {u1x8v = 1; d1x8v = 0;}
   if(MaH12v == MaH1pr2v){u1x8v = 0; d1x8v = 0;}
   if(MaH42v < MaH4pr2v) {u2x8v = 0; d2x8v = 1;}
   if(MaH42v > MaH4pr2v) {u2x8v = 1; d2x8v = 0;}
   if(MaH42v == MaH4pr2v){u2x8v = 0; d2x8v = 0;}
   if(MaD12v < MaD1pr2v) {u3x8v = 0; d3x8v = 1;}
   if(MaD12v > MaD1pr2v) {u3x8v = 1; d3x8v = 0;}
   if(MaD12v == MaD1pr2v){u3x8v = 0; d3x8v = 0;}

   if(MaH13v < MaH1pr3v) {u1x13v = 0; d1x13v = 1;}
   if(MaH13v > MaH1pr3v) {u1x13v = 1; d1x13v = 0;}
   if(MaH13v == MaH1pr3v){u1x13v = 0; d1x13v = 0;}
   if(MaH43v < MaH4pr3v) {u2x13v = 0; d2x13v = 1;}
   if(MaH43v > MaH4pr3v) {u2x13v = 1; d2x13v = 0;}
   if(MaH43v == MaH4pr3v){u2x13v = 0; d2x13v = 0;}
   if(MaD13v < MaD1pr3v) {u3x13v = 0; d3x13v = 1;}
   if(MaD13v > MaD1pr3v) {u3x13v = 1; d3x13v = 0;}
   if(MaD13v == MaD1pr3v){u3x13v = 0; d3x13v = 0;}

   if(MaH14v < MaH1pr4v) {u1x21v = 0; d1x21v = 1;}
   if(MaH14v > MaH1pr4v) {u1x21v = 1; d1x21v = 0;}
   if(MaH14v == MaH1pr4v){u1x21v = 0; d1x21v = 0;}
   if(MaH44v < MaH4pr4v) {u2x21v = 0; d2x21v = 1;}
   if(MaH44v > MaH4pr4v) {u2x21v = 1; d2x21v = 0;}
   if(MaH44v == MaH4pr4v){u2x21v = 0; d2x21v = 0;}
   if(MaD14v < MaD1pr4v) {u3x21v = 0; d3x21v = 1;}
   if(MaD14v > MaD1pr4v) {u3x21v = 1; d3x21v = 0;}
   if(MaD14v == MaD1pr4v){u3x21v = 0; d3x21v = 0;}

   if(MaH15v < MaH1pr5v) {u1x34v = 0; d1x34v = 1;}
   if(MaH15v > MaH1pr5v) {u1x34v = 1; d1x34v = 0;}
   if(MaH15v == MaH1pr5v){u1x34v = 0; d1x34v = 0;}
   if(MaH45v < MaH4pr5v) {u2x34v = 0; d2x34v = 1;}
   if(MaH45v > MaH4pr5v) {u2x34v = 1; d2x34v = 0;}
   if(MaH45v == MaH4pr5v){u2x34v = 0; d2x34v = 0;}
   if(MaD15v < MaD1pr5v) {u3x34v = 0; d3x34v = 1;}
   if(MaD15v > MaD1pr5v) {u3x34v = 1; d3x34v = 0;}
   if(MaD15v == MaD1pr5v){u3x34v = 0; d3x34v = 0;}

   double  acv  = iAC(NULL, TimeFrame1, 0);
   double  ac1v = iAC(NULL, TimeFrame1, 1);
   double  ac2v = iAC(NULL, TimeFrame1, 2);
   double  ac3v = iAC(NULL, TimeFrame1, 3);

   if((ac1v>ac2v && ac2v>ac3v && acv<0 && acv>ac1v)||(acv>ac1v && ac1v>ac2v && acv>0)) {u1acv = 3; d1acv = 0;}
   if((ac1v<ac2v && ac2v<ac3v && acv>0 && acv<ac1v)||(acv<ac1v && ac1v<ac2v && acv<0)) {u1acv = 0; d1acv = 3;}
   if((((ac1v<ac2v || ac2v<ac3v) && acv<0 && acv>ac1v) || (acv>ac1v && ac1v<ac2v && acv>0))
      || (((ac1v>ac2v || ac2v>ac3v) && acv>0 && acv<ac1v) || (acv<ac1v && ac1v>ac2v && acv<0)))
     {u1acv=0; d1acv=0;}

   double  ac03v = iAC(NULL, TimeFrame3, 0);
   double  ac13v = iAC(NULL, TimeFrame3, 1);
   double  ac23v = iAC(NULL, TimeFrame3, 2);
   double  ac33v = iAC(NULL, TimeFrame3, 3);

   if((ac13v>ac23v && ac23v>ac33v && ac03v<0 && ac03v>ac13v)||(ac03v>ac13v && ac13v>ac23v && ac03v>0)) {u3acv = 3; d3acv = 0;}
   if((ac13v<ac23v && ac23v<ac33v && ac03v>0 && ac03v<ac13v)||(ac03v<ac13v && ac13v<ac23v && ac03v<0)) {u3acv = 0; d3acv = 3;}
   if((((ac13v<ac23v || ac23v<ac33v) && ac03v<0 && ac03v>ac13v) || (ac03v>ac13v && ac13v<ac23v && ac03v>0))
      || (((ac13v>ac23v || ac23v>ac33v) && ac03v>0 && ac03v<ac13v) || (ac03v<ac13v && ac13v>ac23v && ac03v<0)))
     {u3acv=0; d3acv=0;}

   double uitog1v = (u1x5v + u1x8v + u1x13v + u1x21v + u1x34v + u1acv) * 12.5;
   double uitog2v = (u2x5v + u2x8v + u2x13v + u2x21v + u2x34v + u2acv) * 12.5;
   double uitog3v = (u3x5v + u3x8v + u3x13v + u3x21v + u3x34v + u3acv) * 12.5;

   double ditog1v = (d1x5v + d1x8v + d1x13v + d1x21v + d1x34v + d1acv) * 12.5;
   double ditog2v = (d2x5v + d2x8v + d2x13v + d2x21v + d2x34v + d2acv) * 12.5;
   double ditog3v = (d3x5v + d3x8v + d3x13v + d3x21v + d3x34v + d3acv) * 12.5;

   int aux=0;
   if(uitog1v>50  && uitog2v>50  && uitog3v>50) aux=1;
   if(ditog1v>50  && ditog2v>50  && ditog3v>50) aux=-1;
   if(uitog1v>=75 && uitog2v>=75 && uitog3v>=75) aux=2;
   if(ditog1v>=75 && ditog2v>=75 && ditog3v>=75) aux=-2;

   return(aux);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int GetStrengthTrend()
  {
   double adxMain=iADX(Symbol(),PERIOD_M15,14,PRICE_MEDIAN,MODE_MAIN,0);
   double adxDiPlus=iADX(Symbol(),PERIOD_M15,14,PRICE_MEDIAN,MODE_PLUSDI,0);
   double adxDiMinus=iADX(Symbol(),PERIOD_M15,14,PRICE_MEDIAN,MODE_MINUSDI,0);

   int strngth=0;
   if(adxMain>25 && adxDiPlus>=25 && adxDiMinus<=15) strngth=1;
   else if(adxMain>25 && adxDiMinus>=25 && adxDiPlus<=15) strngth=-1;
   if(adxMain>35 && adxDiPlus>=25 && adxDiMinus<=15) strngth=2;
   else if(adxMain>35 && adxDiMinus>=25 && adxDiPlus<=15) strngth=-2;

   return(strngth);
  }

// ------------------------------------------------------------------------------------------------
// Trade
// ------------------------------------------------------------------------------------------------
int ordersToLock[];
double signal=0;
int strength=0;
bool buy=false;
bool sell=false;
bool previous_buy=false;
bool previous_sell=false;
double last_open_price=0;
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Trade()
  {
   RefreshRates();
   signal=CalculaSignal();
   string comment=key+signal+"; Trend: "+strength+"; TF: "+Period();

   Comment("\n"+comment);

   previous_buy=buy;
   previous_sell=sell;
   buy = signal>0;
   sell= signal<0;

   double pr=GetPfofit();
   double atr=iATR(Symbol(),0,atr_period+orders,0);
   double tp_val=(use_dynamic_tp==1) ? atr/0.00001 : user_tp;
   double tp = tp_val*MarketInfo(Symbol(),MODE_POINT)*(MarketInfo(Symbol(),MODE_DIGITS) >= 4 ? 2 : 1);
   double sl = tp*-1;
   bool trend_changed=((buy && direction==2) || (sell && direction==1));
   double satisfactorily_tp=((MarketInfo(Symbol(),MODE_BID)+MarketInfo(Symbol(),MODE_ASK))/2-tp)*(CalcularVolumen()/min_lots)/2;

   int total=0;
   int TradeList[][2];
   int ctTrade= 0;
   if((orders>=0 &&((pr>=satisfactorily_tp && (safety || !use_basic_tp))||((trend_changed||(orders>=max_orders && max_orders>1)) && pr>=0))))
     {
      total=OrdersTotal();
      ctTrade=0;
      ArrayResize(TradeList,ctTrade);

      for(int k=total-1; k>=0; k--)
        {
         if(OrderSelect(k,SELECT_BY_POS))
           {
            if(global_basket)
              {
               if((OrderMagicNumber()==magic || OrderMagicNumber()==magic+magic_lock))
                 {
                  ArrayResize(TradeList,++ctTrade);
                  TradeList[ctTrade - 1][0] = OrderOpenTime();
                  TradeList[ctTrade - 1][1] = OrderTicket();
                 }
              }
            else
              {
               if(OrderSymbol()==Symbol() && (OrderMagicNumber()==magic || OrderMagicNumber()==magic+magic_lock))
                 {
                  ArrayResize(TradeList,++ctTrade);
                  TradeList[ctTrade - 1][0] = OrderOpenTime();
                  TradeList[ctTrade - 1][1] = OrderTicket();
                 }
              }
           }
        }

      if(ArraySize(TradeList)>0) ArraySort(TradeList,WHOLE_ARRAY,0,MODE_ASCEND);
      for(int i=0; i<ctTrade; i++)
        {
         OrderSelect(TradeList[i][1],SELECT_BY_TICKET);
         switch(OrderType())
           {
            case OP_BUY       : OrderCloseReliable(OrderTicket(),OrderLots(),MarketInfo(Symbol(),MODE_BID),slippage,Red);
            break;
            case OP_SELL      : OrderCloseReliable(OrderTicket(),OrderLots(),MarketInfo(Symbol(),MODE_ASK),slippage,Red);
            break;
            case OP_BUYLIMIT  :
            case OP_BUYSTOP   :
            case OP_SELLLIMIT :
            case OP_SELLSTOP  : OrderDelete(OrderTicket());
            break;
           }
         if((OrderMagicNumber()==magic || OrderMagicNumber()==magic+magic_lock)) orders--;
        }
     }

   if(!use_basic_sl && close_loss_orders && trend_changed)
     {
      total=OrdersTotal();
      ctTrade=0;
      ArrayResize(TradeList,ctTrade);

      for(k=total-1; k>=0; k--)
        {
         OrderSelect(k,SELECT_BY_POS);
         if(OrderSymbol()!=Symbol()) continue;
         if(OrderType()==OP_BUY)
           {
            double prb=(MarketInfo(Symbol(),MODE_ASK)-OrderOpenPrice());
            if(prb<sl)
              {
               ArrayResize(TradeList,++ctTrade);
               TradeList[ctTrade - 1][0] = OrderOpenTime();
               TradeList[ctTrade - 1][1] = OrderTicket();
              }
           }
         if(OrderType()==OP_SELL)
           {
            double prs=(OrderOpenPrice()-MarketInfo(Symbol(),MODE_BID));
            if(prs<sl)
              {
               ArrayResize(TradeList,++ctTrade);
               TradeList[ctTrade - 1][0] = OrderOpenTime();
               TradeList[ctTrade - 1][1] = OrderTicket();
              }
           }
        }

      if(ArraySize(TradeList)>0) ArraySort(TradeList,WHOLE_ARRAY,0,MODE_ASCEND);
      for(i=0; i<ctTrade; i++)
        {
         if(OrderSelect(TradeList[i][1],SELECT_BY_TICKET))
           {
            if(OrderType()==OP_BUY) OrderCloseReliable(OrderTicket(),OrderLots(),MarketInfo(Symbol(),MODE_BID),slippage,Red);
            if(OrderType()==OP_SELL) OrderCloseReliable(OrderTicket(),OrderLots(),MarketInfo(Symbol(),MODE_ASK),slippage,Red);
            if((OrderMagicNumber()==magic || OrderMagicNumber()==magic+magic_lock)) orders--;
           }
        }
     }

   total=OrdersTotal();
   if(total>0)
     {
      ctTrade=0;
      ArrayResize(TradeList,ctTrade);
      for(k=total; k>=0; k--)
        {
         if(OrderSelect(k,SELECT_BY_POS) && OrderMagicNumber()==magic+magic_lock)
           {
            if(OrderType()!=OP_BUY && OrderType()!=OP_SELL)
              {
               int locker=OrderTicket();
               datetime locker_time=OrderOpenTime();
               int lockerParent=OrderComment();
               if(OrderSelect(lockerParent,SELECT_BY_TICKET))
                 {
                  double profit=OrderProfit()+OrderSwap()-OrderCommission();
                  if((profit>0 && GetStrengthTrend()!=0) || profit>=1)
                    {
                     ArrayResize(TradeList,++ctTrade);
                     TradeList[ctTrade - 1][0] = locker_time;
                     TradeList[ctTrade - 1][1] = locker;
                    }
                 }
              }
            else
              {
               lockerParent=OrderComment();
               if(OrderSelect(lockerParent,SELECT_BY_TICKET) && OrderType()!=OP_BUY && OrderType()!=OP_SELL)
                 {
                  profit=OrderProfit()+OrderSwap()-OrderCommission();
                  if(profit>0 && GetStrengthTrend()!=0)
                    {
                     ArrayResize(TradeList,++ctTrade);
                     TradeList[ctTrade - 1][0] = OrderOpenTime();
                     TradeList[ctTrade - 1][1] = OrderTicket();
                    }
                 }
              }
           }
        }

      if(ArraySize(TradeList)>0) ArraySort(TradeList,WHOLE_ARRAY,0,MODE_ASCEND);
      for(i=0; i<ctTrade; i++)
        {
         if(OrderSelect(TradeList[i][1],SELECT_BY_TICKET)) OrderDelete(OrderTicket());
        }
     }

   ActualizarOrdenes();

   if(buy || sell)
     {
      double new_sl=0;
      double new_open_price=0;
      double limit_price=0;
      if(buy)
        {
         new_sl=GetStopLoss(OP_BUY);
         new_open_price=MarketInfo(Symbol(),MODE_ASK);
         limit_price=new_sl!=0 ? new_sl : MarketInfo(Symbol(),MODE_BID)+sl;
        }
      if(sell)
        {
         new_sl=GetStopLoss(OP_SELL);
         new_open_price=MarketInfo(Symbol(),MODE_BID);
         limit_price=new_sl!=0 ? new_sl : MarketInfo(Symbol(),MODE_ASK)-sl;
        }
      double diff=MathAbs(new_open_price-last_open_price);

      if(orders>=0 && orders<max_orders && ((!trend_changed && diff>=tp) || trend_changed))
        {
         double val=CalcularVolumen();
         if(buy)
           {
            int t1=OrderSendReliable(Symbol(),OP_BUYSTOP,val,new_open_price,slippage,new_sl,GetTakeProfit(OP_BUY),comment,magic,0,Blue);
            direction=1;
            last_open_price=new_open_price;

            if(use_reverse_orders && t1>0 && signal<=1)
              {
               int tl1=OrderSendReliable(Symbol(),OP_SELLSTOP,val,limit_price,slippage,new_open_price-sl,limit_price-(new_open_price-limit_price),t1,magic+magic_lock,0,Red);
              }
           }
         if(sell)
           {
            int t2=OrderSendReliable(Symbol(),OP_SELLSTOP,val,new_open_price,slippage,new_sl,GetTakeProfit(OP_SELL),comment,magic,0,Red);
            direction=2;
            last_open_price=new_open_price;

            if(use_reverse_orders && t2>0 && signal>=-1)
              {
               int tl2=OrderSendReliable(Symbol(),OP_BUYSTOP,val,limit_price,slippage,new_open_price+sl,limit_price+(limit_price-new_open_price),t2,magic+magic_lock,0,Blue);
              }
           }
        }
     }

   if(ts_enable) TrailingStop();
  }
//=============================================================================
//							 OrderSendReliable()
//
//	This is intended to be a drop-in replacement for OrderSend() which, 
//	one hopes, is more resistant to various forms of errors prevalent 
//	with MetaTrader.
//			  
//	RETURN VALUE: 
//
//	Ticket number or -1 under some error conditions.  Check
// final error returned by Metatrader with OrderReliableLastErr().
// This will reset the value from GetLastError(), so in that sense it cannot
// be a total drop-in replacement due to Metatrader flaw. 
//
//	FEATURES:
//
//		 * Re-trying under some error conditions, sleeping a random 
//		   time defined by an exponential probability distribution.
//
//		 * Automatic normalization of Digits
//
//		 * Automatically makes sure that stop levels are more than
//		   the minimum stop distance, as given by the server. If they
//		   are too close, they are adjusted.
//
//		 * Automatically converts stop orders to market orders 
//		   when the stop orders are rejected by the server for 
//		   being to close to market.  NOTE: This intentionally
//       applies only to OP_BUYSTOP and OP_SELLSTOP, 
//       OP_BUYLIMIT and OP_SELLLIMIT are not converted to market
//       orders and so for prices which are too close to current
//       this function is likely to loop a few times and return
//       with the "invalid stops" error message. 
//       Note, the commentary in previous versions erroneously said
//       that limit orders would be converted.  Note also
//       that entering a BUYSTOP or SELLSTOP new order is distinct
//       from setting a stoploss on an outstanding order; use
//       OrderModifyReliable() for that. 
//
//		 * Displays various error messages on the log for debugging.
//
//
//	Matt Kennel, 2006-05-28 and following
//
//=============================================================================
int OrderSendReliable(string symbol,int cmd,double volume,double price,
                      int slippage,double stoploss,double takeprofit,
                      string comment,int magic,datetime expiration=0,
                      color arrow_color=CLR_NONE)
  {

// ------------------------------------------------
// Check basic conditions see if trade is possible. 
// ------------------------------------------------
   OrderReliable_Fname="OrderSendReliable";
   OrderReliablePrint(" attempted "+OrderReliable_CommandString(cmd)+" "+volume+
                      " lots @"+price+" sl:"+stoploss+" tp:"+takeprofit);
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
   if(IsStopped())
     {
      OrderReliablePrint("error: IsStopped() == true");
      _OR_err=ERR_COMMON_ERROR;
      return(-1);
     }

   int cnt=0;
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
   while(!IsTradeAllowed() && cnt<retry_attempts)
     {
      OrderReliable_SleepRandomTime(sleep_time,sleep_maximum);
      cnt++;
     }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
   if(!IsTradeAllowed())
     {
      OrderReliablePrint("error: no operation possible because IsTradeAllowed()==false, even after retries.");
      _OR_err=ERR_TRADE_CONTEXT_BUSY;

      return(-1);
     }

// Normalize all price / stoploss / takeprofit to the proper # of digits.
   int digits=MarketInfo(symbol,MODE_DIGITS);
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
   if(digits>0)
     {
      price=NormalizeDouble(price,digits);
      stoploss=NormalizeDouble(stoploss,digits);
      takeprofit=NormalizeDouble(takeprofit,digits);
     }

   if(stoploss!=0)
      OrderReliable_EnsureValidStop(symbol,price,stoploss);

   int err=GetLastError(); // clear the global variable.  
   err=0;
   _OR_err=0;
   bool exit_loop=false;
   bool limit_to_market=false;

// limit/stop order. 
   int ticket=-1;
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
   if((cmd==OP_BUYSTOP) || (cmd==OP_SELLSTOP) || (cmd==OP_BUYLIMIT) || (cmd==OP_SELLLIMIT))
     {
      cnt=0;
      while(!exit_loop)
        {
         if(IsTradeAllowed())
           {
            ticket=OrderSend(symbol,cmd,volume,price,slippage,stoploss,
                             takeprofit,comment,magic,expiration,arrow_color);
            err=GetLastError();
            _OR_err=err;
           }
         else
           {
            cnt++;
           }

         switch(err)
           {
            case ERR_NO_ERROR:
               exit_loop=true;
               break;

               // retryable errors
            case ERR_SERVER_BUSY:
            case ERR_NO_CONNECTION:
            case ERR_INVALID_PRICE:
            case ERR_OFF_QUOTES:
            case ERR_BROKER_BUSY:
            case ERR_TRADE_CONTEXT_BUSY:
               cnt++;
               break;

            case ERR_PRICE_CHANGED:
            case ERR_REQUOTE:
               RefreshRates();
               continue;   // we can apparently retry immediately according to MT docs.

            case ERR_INVALID_STOPS:
               double servers_min_stop=MarketInfo(symbol,MODE_STOPLEVEL)*MarketInfo(symbol,MODE_POINT);
               if(cmd==OP_BUYSTOP)
                 {
                  // If we are too close to put in a limit/stop order so go to market.
                  if(MathAbs(MarketInfo(symbol,MODE_ASK)-price)<=servers_min_stop)
                     limit_to_market=true;

                 }
               else if(cmd==OP_SELLSTOP)
                 {
                  // If we are too close to put in a limit/stop order so go to market.
                  if(MathAbs(MarketInfo(symbol,MODE_BID)-price)<=servers_min_stop)
                     limit_to_market=true;
                 }
               exit_loop=true;
               break;

            default:
               // an apparently serious error.
               exit_loop=true;
               break;

           }  // end switch 

         if(cnt>retry_attempts)
            exit_loop=true;

         if(exit_loop)
           {
            if(err!=ERR_NO_ERROR)
              {
               OrderReliablePrint("non-retryable error: "+OrderReliableErrTxt(err));
              }
            if(cnt>retry_attempts)
              {
               OrderReliablePrint("retry attempts maxed at "+retry_attempts);
              }
           }

         if(!exit_loop)
           {
            OrderReliablePrint("retryable error ("+cnt+"/"+retry_attempts+
                               "): "+OrderReliableErrTxt(err));
            OrderReliable_SleepRandomTime(sleep_time,sleep_maximum);
            RefreshRates();
           }
        }

      // We have now exited from loop. 
      if(err==ERR_NO_ERROR)
        {
         OrderReliablePrint("apparently successful OP_BUYSTOP or OP_SELLSTOP order placed, details follow.");
         OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES);
         OrderPrint();
         return(ticket); // SUCCESS! 
        }
      if(!limit_to_market)
        {
         OrderReliablePrint("failed to execute stop or limit order after "+cnt+" retries");
         OrderReliablePrint("failed trade: "+OrderReliable_CommandString(cmd)+" "+symbol+
                            "@"+price+" tp@"+takeprofit+" sl@"+stoploss);
         OrderReliablePrint("last error: "+OrderReliableErrTxt(err));
         return(-1);
        }
     }  // end	  
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
   if(limit_to_market)
     {
      OrderReliablePrint("going from limit order to market order because market is too close.");
      if((cmd==OP_BUYSTOP) || (cmd==OP_BUYLIMIT))
        {
         cmd=OP_BUY;
         price=MarketInfo(symbol,MODE_ASK);
        }
      else if((cmd==OP_SELLSTOP) || (cmd==OP_SELLLIMIT))
        {
         cmd=OP_SELL;
         price=MarketInfo(symbol,MODE_BID);
        }
     }

// we now have a market order.
   err=GetLastError(); // so we clear the global variable.  
   err= 0;
   _OR_err= 0;
   ticket = -1;
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
   if((cmd==OP_BUY) || (cmd==OP_SELL))
     {
      cnt=0;
      while(!exit_loop)
        {
         if(IsTradeAllowed())
           {
            ticket=OrderSend(symbol,cmd,volume,price,slippage,
                             stoploss,takeprofit,comment,magic,
                             expiration,arrow_color);
            err=GetLastError();
            _OR_err=err;
           }
         else
           {
            cnt++;
           }
         switch(err)
           {
            case ERR_NO_ERROR:
               exit_loop=true;
               break;

            case ERR_SERVER_BUSY:
            case ERR_NO_CONNECTION:
            case ERR_INVALID_PRICE:
            case ERR_OFF_QUOTES:
            case ERR_BROKER_BUSY:
            case ERR_TRADE_CONTEXT_BUSY:
               cnt++; // a retryable error
               break;

            case ERR_PRICE_CHANGED:
            case ERR_REQUOTE:
               RefreshRates();
               continue; // we can apparently retry immediately according to MT docs.

            default:
               // an apparently serious, unretryable error.
               exit_loop=true;
               break;

           }  // end switch 

         if(cnt>retry_attempts)
            exit_loop=true;

         if(!exit_loop)
           {
            OrderReliablePrint("retryable error ("+cnt+"/"+
                               retry_attempts+"): "+OrderReliableErrTxt(err));
            OrderReliable_SleepRandomTime(sleep_time,sleep_maximum);
            RefreshRates();
           }

         if(exit_loop)
           {
            if(err!=ERR_NO_ERROR)
              {
               OrderReliablePrint("non-retryable error: "+OrderReliableErrTxt(err));
              }
            if(cnt>retry_attempts)
              {
               OrderReliablePrint("retry attempts maxed at "+retry_attempts);
              }
           }
        }

      // we have now exited from loop. 
      if(err==ERR_NO_ERROR)
        {
         OrderReliablePrint("apparently successful OP_BUY or OP_SELL order placed, details follow.");
         OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES);
         OrderPrint();
         return(ticket); // SUCCESS! 
        }
      OrderReliablePrint("failed to execute OP_BUY/OP_SELL, after "+cnt+" retries");
      OrderReliablePrint("failed trade: "+OrderReliable_CommandString(cmd)+" "+symbol+
                         "@"+price+" tp@"+takeprofit+" sl@"+stoploss);
      OrderReliablePrint("last error: "+OrderReliableErrTxt(err));
      return(-1);
     }
  }
//=============================================================================
//							 OrderCloseReliable()
//
//	This is intended to be a drop-in replacement for OrderClose() which, 
//	one hopes, is more resistant to various forms of errors prevalent 
//	with MetaTrader.
//			  
//	RETURN VALUE: 
//
//		TRUE if successful, FALSE otherwise
//
//
//	FEATURES:
//
//		 * Re-trying under some error conditions, sleeping a random 
//		   time defined by an exponential probability distribution.
//
//		 * Displays various error messages on the log for debugging.
//
//
//	Derk Wehler, ashwoods155@yahoo.com  	2006-07-19
//
//=============================================================================
bool OrderCloseReliable(int ticket,double lots,double price,
                        int slippage,color arrow_color=CLR_NONE)
  {
   int nOrderType;
   string strSymbol;
   OrderReliable_Fname="OrderCloseReliable";

   OrderReliablePrint(" attempted close of #"+ticket+" price:"+price+
                      " lots:"+lots+" slippage:"+slippage);
// collect details of order so that we can use GetMarketInfo later if needed
   if(!OrderSelect(ticket,SELECT_BY_TICKET))
     {
      _OR_err=GetLastError();
      OrderReliablePrint("error: "+ErrorDescription(_OR_err));
      return(false);
     }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
   else
     {
      nOrderType= OrderType();
      strSymbol = OrderSymbol();
     }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
   if(nOrderType!=OP_BUY && nOrderType!=OP_SELL)
     {
      _OR_err=ERR_INVALID_TICKET;
      OrderReliablePrint("error: trying to close ticket #"+ticket+", which is "+OrderReliable_CommandString(nOrderType)+", not OP_BUY or OP_SELL");
      return(false);
     }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
   if(IsStopped())
     {
      OrderReliablePrint("error: IsStopped() == true");
      return(false);
     }

   int cnt=0;

   int err=GetLastError(); // so we clear the global variable.  
   err=0;
   _OR_err=0;
   bool exit_loop=false;
   cnt=0;
   bool result=false;
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
   while(!exit_loop)
     {
      if(IsTradeAllowed())
        {
         result=OrderClose(ticket,lots,price,slippage,arrow_color);
         err=GetLastError();
         _OR_err=err;
        }
      else
         cnt++;

      if(result==true)
         exit_loop=true;

      switch(err)
        {
         case ERR_NO_ERROR:
            exit_loop=true;
            break;

         case ERR_SERVER_BUSY:
         case ERR_NO_CONNECTION:
         case ERR_INVALID_PRICE:
         case ERR_OFF_QUOTES:
         case ERR_BROKER_BUSY:
         case ERR_TRADE_CONTEXT_BUSY:
         case ERR_TRADE_TIMEOUT:      // for modify this is a retryable error, I hope. 
            cnt++;    // a retryable error
            break;

         case ERR_PRICE_CHANGED:
         case ERR_REQUOTE:
            continue;    // we can apparently retry immediately according to MT docs.

         default:
            // an apparently serious, unretryable error.
            exit_loop=true;
            break;

        }  // end switch 

      if(cnt>retry_attempts)
         exit_loop=true;

      if(!exit_loop)
        {
         OrderReliablePrint("retryable error ("+cnt+"/"+retry_attempts+
                            "): "+OrderReliableErrTxt(err));
         OrderReliable_SleepRandomTime(sleep_time,sleep_maximum);
         // Added by Paul Hampton-Smith to ensure that price is updated for each retry
         if(nOrderType == OP_BUY)  price = NormalizeDouble(MarketInfo(strSymbol,MODE_BID),MarketInfo(strSymbol,MODE_DIGITS));
         if(nOrderType == OP_SELL) price = NormalizeDouble(MarketInfo(strSymbol,MODE_ASK),MarketInfo(strSymbol,MODE_DIGITS));
        }

      if(exit_loop)
        {
         if((err!=ERR_NO_ERROR) && (err!=ERR_NO_RESULT))
            OrderReliablePrint("non-retryable error: "+OrderReliableErrTxt(err));

         if(cnt>retry_attempts)
            OrderReliablePrint("retry attempts maxed at "+retry_attempts);
        }
     }
// we have now exited from loop. 
   if((result==true) || (err==ERR_NO_ERROR))
     {
      OrderReliablePrint("apparently successful close order, updated trade details follow.");
      OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES);
      OrderPrint();
      return(true); // SUCCESS! 
     }

   OrderReliablePrint("failed to execute close after "+cnt+" retries");
   OrderReliablePrint("failed close: Ticket #"+ticket+", Price: "+
                      price+", Slippage: "+slippage);
   OrderReliablePrint("last error: "+OrderReliableErrTxt(err));

   return(false);
  }
//=============================================================================
//=============================================================================
//								Utility Functions
//=============================================================================
//=============================================================================



int OrderReliableLastErr()
  {
   return (_OR_err);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string OrderReliableErrTxt(int err)
  {
   return ("" + err + ":" + ErrorDescription(err));
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OrderReliablePrint(string s)
  {
// Print to log prepended with stuff;
   if(!(IsTesting() || IsOptimization())) Print(OrderReliable_Fname+" "+OrderReliableVersion+":"+s);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string OrderReliable_CommandString(int cmd)
  {
   if(cmd==OP_BUY)
      return("OP_BUY");

   if(cmd==OP_SELL)
      return("OP_SELL");

   if(cmd==OP_BUYSTOP)
      return("OP_BUYSTOP");

   if(cmd==OP_SELLSTOP)
      return("OP_SELLSTOP");

   if(cmd==OP_BUYLIMIT)
      return("OP_BUYLIMIT");

   if(cmd==OP_SELLLIMIT)
      return("OP_SELLLIMIT");

   return("(CMD==" + cmd + ")");
  }
//=============================================================================
//
//						 OrderReliable_EnsureValidStop()
//
// 	Adjust stop loss so that it is legal.
//
//	Matt Kennel 
//
//=============================================================================
void OrderReliable_EnsureValidStop(string symbol,double price,double &sl)
  {
// Return if no S/L
   if(sl==0)
      return;

   double servers_min_stop=MarketInfo(symbol,MODE_STOPLEVEL)*MarketInfo(symbol,MODE_POINT);
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
   if(MathAbs(price-sl)<=servers_min_stop)
     {
      // we have to adjust the stop.
      if(price>sl)
         sl=price-servers_min_stop;   // we are long

      else if(price<sl)
         sl=price+servers_min_stop;   // we are short

      else
         OrderReliablePrint("EnsureValidStop: error, passed in price == sl, cannot adjust");

      sl=NormalizeDouble(sl,MarketInfo(symbol,MODE_DIGITS));
     }
  }
//=============================================================================
//
//						 OrderReliable_SleepRandomTime()
//
//	This sleeps a random amount of time defined by an exponential 
//	probability distribution. The mean time, in Seconds is given 
//	in 'mean_time'.
//
//	This is the back-off strategy used by Ethernet.  This will 
//	quantize in tenths of seconds, so don't call this with a too 
//	small a number.  This returns immediately if we are backtesting
//	and does not sleep.
//
//	Matt Kennel mbkennelfx@gmail.com.
//
//=============================================================================
void OrderReliable_SleepRandomTime(double mean_time,double max_time)
  {
   if(IsTesting())
      return;    // return immediately if backtesting.

   double tenths=MathCeil(mean_time/0.1);
   if(tenths<=0)
      return;

   int maxtenths=MathRound(max_time/0.1);
   double p=1.0-1.0/tenths;

   Sleep(100);    // one tenth of a second PREVIOUS VERSIONS WERE STUPID HERE. 

   for(int i=0; i<maxtenths; i++)
      //+------------------------------------------------------------------+
      //|                                                                  |
      //+------------------------------------------------------------------+
      //+------------------------------------------------------------------+
      //|                                                                  |
      //+------------------------------------------------------------------+
      //+------------------------------------------------------------------+
      //|                                                                  |
      //+------------------------------------------------------------------+
     {
      if(MathRand()>p*32768)
         break;

      // MathRand() returns in 0..32767
      Sleep(100);
     }
  }
//+------------------------------------------------------------------+
