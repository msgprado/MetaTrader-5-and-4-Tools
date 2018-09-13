//
// Trade Manager.mq4
// getYourNet.ch
//

#property copyright "Copyright 2018, getYourNet.ch"

#include <..\Libraries\stdlib.mq4>

enum TypeStopLossPercentBalanceAction
{
   CloseWorstTrade,
   CloseAllTrades
};

input double BreakEvenAfterPips = 5;
input double AboveBEPips = 1;
input double StartTrailingPips = 7;
input double StopLossPips = 0;
input bool HedgeAtStopLoss = false;
input double StopLossPercentBalance = 0;
input TypeStopLossPercentBalanceAction StopLossPercentBalanceAction = CloseWorstTrade;
input bool ActivateTrailing = true;
input double TrailingFactor = 0.6;
input double OpenLots = 0.01;
input bool ShowInfo = true;
input color TextColor = Gray;
input int FontSize = 9;
input int TextGap = 16;
input bool ManageOwnTradesOnly = true;
input int ManageMagicNumberOnly = 0;
input int ManageOrderNumberOnly = 0;
input bool SwitchSymbolClickAllCharts = true;
input bool DrawLevelsAllCharts = true;
input bool DrawBackgroundPanel = true;
input int BackgroundPanelWidth = 200;
input color BackgroundPanelColor = clrNONE;

string namespace="Trade Manager";
bool working=false;
double pipsfactor;
datetime lasttick;
datetime lasterrortime;
string lasterrorstring;
bool istesting;
bool initerror;
string ExtraChars = "";
string tickchar="";
int basemagicnumber=50000000;
int hedgeoffsetmagicnumber=10000;
int closeallcommand=false;
double _BreakEvenAfterPips;
double _AboveBEPips;
double _StartTrailingPips;
double _StopLossPips;
double _OpenLots;

enum BEStopModes
{
   None=1,
   HardSingle=2,
   SoftBasket=3
};

struct TypeWorkingState
{
   BEStopModes StopMode;
   bool closebasketatBE;
   bool ManualBEStopLocked;
   bool SoftBEStopLocked;
   double closedlosses;
   double peakgain;
   double peakpips;
   bool TrailingActivated;
   int currentbasemagicnumber;
   void Init()
   {
      closebasketatBE=false;
      ManualBEStopLocked=false;
      SoftBEStopLocked=false;
      StopMode=SoftBasket;
      closedlosses=0;
      peakgain=0;
      peakpips=0;
      TrailingActivated=false;
      currentbasemagicnumber=basemagicnumber;
   };
   void Reset()
   {
      closebasketatBE=false;
      ManualBEStopLocked=false;
      SoftBEStopLocked=false;
      closedlosses=0;
      peakgain=0;
      peakpips=0;
      TrailingActivated=false;
      currentbasemagicnumber=basemagicnumber;
   };
   void ResetLocks()
   {
      ManualBEStopLocked=false;
      SoftBEStopLocked=false;
   };
};
TypeWorkingState WS;

struct TypeBasketInfo
{
   double gain;
   double gainpips;
   double gainpipsplus;
   double gainpipsminus;
   double volumeplus;
   double volumeminus;
   int buys;
   int sells;
   double buyvolume;
   double sellvolume;
   int managedorders;
   string pairsintrades[];
   void Init()
   {
      gain=0;
      gainpips=0;
      gainpipsplus=0;
      gainpipsminus=0;
      volumeplus=0;
      volumeminus=0;
      buys=0;
      sells=0;
      buyvolume=0;
      sellvolume=0;
      managedorders=0;
      ArrayResize(pairsintrades,0);
   };
};
TypeBasketInfo BI;


void OnInit()
{
   initerror=false;

   istesting=MQLInfoInteger(MQL_TESTER);

   ExtraChars = StringSubstr(Symbol(), 6);

   pipsfactor=1;
   
   lasttick=TimeLocal();

   if(Digits==5||Digits==3)
      pipsfactor=10;

   _BreakEvenAfterPips=BreakEvenAfterPips*pipsfactor;
   _AboveBEPips=AboveBEPips*pipsfactor;
   _StopLossPips=StopLossPips*pipsfactor;
   _StartTrailingPips=StartTrailingPips*pipsfactor;
   _OpenLots=OpenLots;

   WS.Init();
   
   GetGlobalVariables();

   if(DrawBackgroundPanel)
   {
      string objname=namespace+"-"+"Panel";
      ObjectCreate(0,objname,OBJ_RECTANGLE_LABEL,0,0,0,0,0);
      ObjectSetInteger(0,objname,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
      ObjectSetInteger(0,objname,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(0,objname,OBJPROP_WIDTH,1);
      ObjectSetInteger(0,objname,OBJPROP_XDISTANCE,BackgroundPanelWidth);
      ObjectSetInteger(0,objname,OBJPROP_YDISTANCE,TextGap);
      ObjectSetInteger(0,objname,OBJPROP_XSIZE,BackgroundPanelWidth);
      ObjectSetInteger(0,objname,OBJPROP_YSIZE,10000);
      color c=ChartGetInteger(0,CHART_COLOR_BACKGROUND);
      if(BackgroundPanelColor!=clrNONE)
         c=BackgroundPanelColor;
      ObjectSetInteger(0,objname,OBJPROP_COLOR,c);
      ObjectSetInteger(0,objname,OBJPROP_BGCOLOR,c);
   }
   
   if(istesting)
   {
      OpenBuy();
      OpenBuy();
      OpenBuy();
   }

   if(!EventSetMillisecondTimer(200)&&!istesting)
      initerror=true;
}


void OnDeinit(const int reason)
{
   EventKillTimer();
   if(!istesting)
      DeleteAllObjects();
   SetGlobalVariables();
}


void OnTick()
{
   lasttick=TimeLocal();
   Manage();
}


void OnTimer()
{
   int lastctrlspan=TimeLocal()-lastctrl;
   if(lastctrlspan>1)
   {
      DeleteLevels();
      DeleteLegend();
   }
   Manage();
}


void Manage()
{
   if(working||initerror)
      return;
   working=true;
   if(closeallcommand)
      CloseAllInternal();
   ManageOrders();
   ManageBasket();
   DisplayText();
   working=false;
}


void SetBEClose()
{
   if(BI.gain<0)
   {
      WS.closebasketatBE=!WS.closebasketatBE;
   }
   if(BI.gain>=0)
   {
      WS.ManualBEStopLocked=!WS.ManualBEStopLocked;
   }
}


void SetSoftStopMode()
{
   if(WS.StopMode==None)
      WS.StopMode=SoftBasket;
   else if(WS.StopMode==HardSingle)
      WS.StopMode=None;
   else
      WS.StopMode=None;

   WS.ResetLocks();
      
   SetGlobalVariables();
}


void SetHardStopMode()
{
   if(WS.StopMode==None)
      WS.StopMode=HardSingle;
   else if(WS.StopMode==SoftBasket)
      WS.StopMode=None;
   else
      WS.StopMode=None;

   WS.ResetLocks();
      
   SetGlobalVariables();
}


void SetGlobalVariables()
{
   GlobalVariableSet(namespace+"StopMode",WS.StopMode);
   GlobalVariableSet(namespace+"closedlosses",WS.closedlosses);
   GlobalVariableSet(namespace+"peakgain",WS.peakgain);
   GlobalVariableSet(namespace+"peakpips",WS.peakpips);
}


void GetGlobalVariables()
{
   string varname=namespace+"StopMode";
   if(GlobalVariableCheck(varname))
      WS.StopMode=(BEStopModes)GlobalVariableGet(varname);
   varname=namespace+"closedlosses";
   if(GlobalVariableCheck(varname))
      WS.closedlosses=GlobalVariableGet(varname);
   varname=namespace+"peakgain";
   if(GlobalVariableCheck(varname))
      WS.peakgain=GlobalVariableGet(varname);
   varname=namespace+"peakpips";
   if(GlobalVariableCheck(varname))
      WS.peakpips=GlobalVariableGet(varname);
}


bool IsOrderToManage()
{
   bool manage=true,
   ismagicnumber=(OrderMagicNumber()==ManageMagicNumberOnly),
   isinternalmagicnumber=(OrderMagicNumber()>=basemagicnumber)&&(OrderMagicNumber()<=basemagicnumber+(hedgeoffsetmagicnumber*2)),
   isordernumber=(OrderTicket()==ManageOrderNumberOnly);
   
   if((ManageMagicNumberOnly>0&&!ismagicnumber)||(ManageOwnTradesOnly&&ManageMagicNumberOnly==0&&!isinternalmagicnumber))
      manage=false;
   
   if(ManageOrderNumberOnly>0&&!isordernumber)
      manage=false;
   return manage;
}


void ManageOrders()
{
   int cnt, ordertotal=OrdersTotal(), largestlossindex=-1;
   double largestloss=0;

   BI.Init();
   
   for(cnt=ordertotal-1;cnt>=0;cnt--)
   {
      if(OrderSelect(cnt, SELECT_BY_POS, MODE_TRADES))
      {
         if(IsOrderToManage())
         {
            double tickvalue=MarketInfo(OrderSymbol(),MODE_TICKVALUE);
            double gainpips=((OrderProfit()+OrderCommission()+OrderSwap())/OrderLots())/tickvalue;
            
            if(_StopLossPips>0&&(gainpips+_StopLossPips)<0)
            {
               //if(HedgeAtStopLoss)
               //   OpenOrder(hedgeordertype,OrderLots());
               //else
               
               CloseSelectedOrder();
            }
            else
            {
               int om=OrderMagicNumber();
               if(om>=basemagicnumber+hedgeoffsetmagicnumber)
                  om-=hedgeoffsetmagicnumber;
               if(om>=basemagicnumber&&om>=WS.currentbasemagicnumber)
                  WS.currentbasemagicnumber=(om+1);

               double BESL=0;
               bool NeedSetSL=false;
               int hedgeordertype=0;
               if(OrderType()==OP_SELL)
               {
                  hedgeordertype=OP_BUY;
                  BESL=OrderOpenPrice()-(_AboveBEPips*Point);
                  BI.sells++;
                  BI.sellvolume+=OrderLots();
                  if(OrderStopLoss()==0||OrderStopLoss()>BESL)
                     NeedSetSL=true;
               }
               if(OrderType()==OP_BUY)
               {
                  hedgeordertype=OP_SELL;
                  BESL=OrderOpenPrice()+(_AboveBEPips*Point);
                  BI.buys++;
                  BI.buyvolume+=OrderLots();
                  if(OrderStopLoss()==0||OrderStopLoss()<BESL)
                     NeedSetSL=true;
               }

               double ordergain=OrderProfit()+OrderCommission()+OrderSwap();
               if(ordergain<0&&ordergain<largestloss)
               {
                  largestlossindex=cnt;
                  largestloss=ordergain;
               }
               BI.gain+=ordergain;

               BI.managedorders++;
               AddPairsInTrades(OrderSymbol());

               if(gainpips<0)
               {
                  BI.gainpipsminus+=gainpips*OrderLots()*tickvalue;
                  BI.volumeminus+=OrderLots()*tickvalue;
               }
               else
               {
                  BI.gainpipsplus+=gainpips*OrderLots()*tickvalue;
                  BI.volumeplus+=OrderLots()*tickvalue;
               }
               
               if(WS.StopMode==HardSingle&&gainpips>=_BreakEvenAfterPips&&NeedSetSL)
               {
                  SetLastErrorBool(OrderModify(OrderTicket(),OrderOpenPrice(),BESL,OrderTakeProfit(),0));
               }
            }
         }
      }
   }
   if(BI.managedorders>0)
   {
      BI.gainpips=(BI.gainpipsplus+BI.gainpipsminus)/(BI.volumeplus+BI.volumeminus);

      if(BI.gainpips>WS.peakpips)
         WS.peakpips=BI.gainpips;
      
      if(BI.gain>WS.peakgain)
         WS.peakgain=BI.gain;

      if(StopLossPercentBalance>0)
      {
         if((BI.gain)+((AccountBalance()/100)*StopLossPercentBalance)<0)
         {
            if(StopLossPercentBalanceAction==CloseWorstTrade)
            {
               if(OrderSelect(largestlossindex, SELECT_BY_POS, MODE_TRADES)&&IsAutoTradingEnabled())
               {
                  if(CloseSelectedOrder())
                  {
                     WS.closedlosses+=largestloss;
                     BI.managedorders--;
                  }
               }
            }
            else if(StopLossPercentBalanceAction==CloseAllTrades)
            {
               CloseAllInternal();
               BI.managedorders=0;
            }
         }
      }
   }
}


void ManageBasket()
{
   if(BI.managedorders==0)
   {
      WS.Reset();
      if(istesting)
      {
         MathSrand(TimeLocal());
         bool buy=(MathRand()%2);
         buy=false;
         if(buy)
         {
            OpenBuy();
            OpenBuy();
            OpenBuy();
         }
         else
         {
            OpenSell();
            OpenSell();
            OpenSell();
         }
      }
      return;
   }

   if(ActivateTrailing&&BI.gainpips>=_StartTrailingPips)
   {
      WS.TrailingActivated=true;
   }

   if(WS.TrailingActivated)
   {
      if(BI.gain<GetTrailingLimit())
         CloseAllInternal();
   }
   
   if(WS.closebasketatBE)
   {
      if(BI.gain>=0)
         CloseAllInternal();
   }
   if(WS.ManualBEStopLocked)
   {
      if(BI.gain<=0)
         CloseAllInternal();
   }
   
   if(WS.StopMode==SoftBasket&&_BreakEvenAfterPips>0&&WS.peakpips>=_BreakEvenAfterPips)
   {
      WS.SoftBEStopLocked=true;   
   }
   
   if(WS.SoftBEStopLocked&&BI.gainpips<_AboveBEPips)
   {
      CloseAllInternal();   
   }
}


double GetTrailingLimit()
{
   return WS.peakgain*TrailingFactor;
}


void DisplayText()
{
   DeleteText();
   if(!ShowInfo)
      return;

   if(tickchar=="")
      tickchar="-";
   else
      tickchar="";

   int rowindex=0;

   if(!IsAutoTradingEnabled())
   {
      CreateLabel(rowindex,FontSize,DeepPink,tickchar+" Autotrading Disabled");
      rowindex++;
   }
   else
   {
      if(TimeLocal()-lasttick>60)
         CreateLabel(rowindex,FontSize,DeepPink,tickchar+" No Market Activity");
      else
         CreateLabel(rowindex,FontSize,MediumSeaGreen,tickchar+" Running");
      rowindex++;
   }

   string stopmodetext="";
   if(WS.StopMode==None)
      stopmodetext="No Break Even Mode";
   if(WS.StopMode==HardSingle)
      stopmodetext="Hard Single Break Even Mode";
   if(WS.StopMode==SoftBasket)
      stopmodetext="Soft Basket Break Even Mode";
   CreateLabel(rowindex,FontSize,TextColor,stopmodetext);
   rowindex++;

   CreateLabel(rowindex,FontSize,TextColor,"Balance: "+DoubleToStr(AccountBalance(),0));
   rowindex++;
   
   CreateLabel(rowindex,FontSize,TextColor,"Free Margin: "+DoubleToStr(AccountFreeMargin(),1));
   rowindex++;

   CreateLabel(rowindex,FontSize,TextColor,"Leverage: "+IntegerToString(AccountInfoInteger(ACCOUNT_LEVERAGE)));
   rowindex++;

   CreateLabel(rowindex,FontSize,TextColor,"Open Volume: "+_OpenLots);
   rowindex++;

   if(BI.managedorders!=0)
   {
      if(BI.buyvolume>0)
      {      
         CreateLabel(rowindex,FontSize,TextColor,IntegerToString(BI.buys)+" Buy: "+DoubleToStr(BI.buyvolume,2));
         rowindex++;
      }
   
      if(BI.sellvolume>0)
      {
         CreateLabel(rowindex,FontSize,TextColor,IntegerToString(BI.sells)+" Sell: "+DoubleToStr(BI.sellvolume,2));
         rowindex++;
      }
   
      CreateLabel(rowindex,FontSize,TextColor,"Pips: "+DoubleToString(BI.gainpips/pipsfactor,1));
      rowindex++;
   
      CreateLabel(rowindex,FontSize,TextColor,"Percent: "+DoubleToString(BI.gain/(AccountBalance()/100),1));
      rowindex++;
   
      color gaincolor=MediumSeaGreen;
      if(BI.gain<0)
         gaincolor=DeepPink;
      CreateLabel(rowindex,(FontSize*2.3),gaincolor,DoubleToStr(BI.gain,2));
      rowindex++;
      rowindex++;
      
      if(WS.closedlosses<0)
      {
         color closedlossescolor=MediumSeaGreen;
         double gaintotal=WS.closedlosses+BI.gain;
         if(gaintotal<0)
            closedlossescolor=DeepPink;
         CreateLabel(rowindex,FontSize,closedlossescolor,DoubleToStr(gaintotal,2));
         rowindex++;
      }
   
      if(WS.closebasketatBE)
      {
         CreateLabel(rowindex,FontSize,DeepPink,"Close Basket at Break Even");
         rowindex++;
      }
   
      if(WS.TrailingActivated)
      {
         CreateLabel(rowindex,FontSize,MediumSeaGreen,"Trailing Activ, Current Limit: "+DoubleToStr(GetTrailingLimit(),2));
         rowindex++;
      }
      else
      {
         if(WS.ManualBEStopLocked)
         {
            CreateLabel(rowindex,FontSize,MediumSeaGreen,"Manual Break Even Stop Locked");
            rowindex++;
         }
      
         if(WS.SoftBEStopLocked)
         {
            CreateLabel(rowindex,FontSize,MediumSeaGreen,"Basket Break Even Stop Locked");
            rowindex++;
         }
      }
   
      int asize=ArraySize(BI.pairsintrades);
      if(asize>0)
         rowindex++;
      for(int i=0; i<asize; i++)
      {
         CreateLabel(rowindex,FontSize,TextColor,BI.pairsintrades[i],"-SymbolButton");
         rowindex++;
      }
   }

   if(TimeLocal()-lasterrortime<3)
   {
      CreateLabel(rowindex,FontSize,DeepPink,lasterrorstring);
      rowindex++;
   }

}


void CreateLabel(int RI, int fontsize, color c, string text, string group="")
{
   string objname=namespace+"-"+"Text"+IntegerToString(RI+1)+group;
   ObjectCreate(0,objname,OBJ_LABEL,0,0,0,0,0);
   ObjectSetInteger(0,objname,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
   ObjectSetInteger(0,objname,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0,objname,OBJPROP_XDISTANCE,5);
   ObjectSetInteger(0,objname,OBJPROP_YDISTANCE,20+(TextGap*RI));
   ObjectSetInteger(0,objname,OBJPROP_COLOR,c);
   ObjectSetInteger(0,objname,OBJPROP_FONTSIZE,fontsize);
   ObjectSetString(0,objname,OBJPROP_FONT,"Arial");
   ObjectSetString(0,objname,OBJPROP_TEXT,text);
}


void DrawLevels()
{
   if(DrawLevelsAllCharts)
   {
      long chartid=ChartFirst();
      while(chartid>-1)
      {
         if(ChartSymbol(chartid)==Symbol())
            DrawLevels(chartid);
         chartid=ChartNext(chartid);
      }
   }
   else
      DrawLevels(0);
}


void DrawLevels(long chartid)
{
   //CreateLevel(chartid,namespace+"-"+"Level1",MediumSeaGreen,Bid-(AboveBEPips*Point));
   //CreateLevel(chartid,namespace+"-"+"Level2",DeepPink,Bid-(BreakEvenAfterPips*Point));
   //CreateLevel(chartid,namespace+"-"+"Level3",MediumSeaGreen,Ask+(AboveBEPips*Point));
   //CreateLevel(chartid,namespace+"-"+"Level4",DeepPink,Ask+(BreakEvenAfterPips*Point));

   if(_StopLossPips>0)
   {
      //CreateRectangle(chartid,namespace+"-"+"Rectangle1",WhiteSmoke,Ask+(StopLossPips*Point),Bid-(StopLossPips*Point));
      CreateLevel(chartid,namespace+"-"+"Level1",DeepPink,Ask+(_StopLossPips*Point));
      CreateLevel(chartid,namespace+"-"+"Level2",DeepPink,Bid-(_StopLossPips*Point));
   }

   CreateRectangle(chartid,namespace+"-"+"Rectangle10",WhiteSmoke,Ask+(_BreakEvenAfterPips*Point),Bid-(_BreakEvenAfterPips*Point));
   CreateRectangle(chartid,namespace+"-"+"Rectangle11",WhiteSmoke,Ask+(_AboveBEPips*Point),Bid-(_AboveBEPips*Point));

   ChartRedraw(chartid);
}


void CreateLevel(long chartid, string objname, color c, double price)
{
   if(ObjectFind(chartid,objname)<0)
   {
      ObjectCreate(chartid,objname,OBJ_HLINE,0,0,0);
      ObjectSetInteger(chartid,objname,OBJPROP_COLOR,c);
      ObjectSetInteger(chartid,objname,OBJPROP_WIDTH,1);
      ObjectSetInteger(chartid,objname,OBJPROP_STYLE,STYLE_DOT);
      ObjectSetInteger(chartid,objname,OBJPROP_BACK,true);
   }
   ObjectSetDouble(chartid,objname,OBJPROP_PRICE,price);
}


void CreateRectangle(long chartid, string objname, color c, double price1, double price2)
{
   if(ObjectFind(chartid,objname)<0)
   {
      ObjectCreate(chartid,objname,OBJ_RECTANGLE,0,0,0);
      ObjectSetInteger(chartid,objname,OBJPROP_COLOR,c);
      ObjectSetInteger(chartid,objname,OBJPROP_BACK,true);
   }
   ObjectSetDouble(chartid,objname,OBJPROP_PRICE1,price1);
   ObjectSetDouble(chartid,objname,OBJPROP_PRICE2,price2);
   ObjectSetInteger(chartid,objname,OBJPROP_TIME1,TimeCurrent()-400000000);
   ObjectSetInteger(chartid,objname,OBJPROP_TIME2,TimeCurrent());
}


void DisplayLegend()
{
   CreateLegend(namespace+"-"+"Legend1",5+(TextGap*2.4),"Hotkeys: Press Ctrl plus");
   CreateLegend(namespace+"-"+"Legend2",5+(TextGap*1.6),"1 Open Buy | 3 Open Sell | 0 Close All");
   CreateLegend(namespace+"-"+"Legend3",5+(TextGap*0.8),"5 Hard SL | 6 Soft SL | 8 Close at BE");
   CreateLegend(namespace+"-"+"Legend4",5+(TextGap*0),"; Decrease Volume | : Increase Volume");
}


void CreateLegend(string objname, int y, string text)
{
   ObjectCreate(0,objname,OBJ_LABEL,0,0,0,0,0);
   ObjectSetInteger(0,objname,OBJPROP_CORNER,CORNER_RIGHT_LOWER);
   ObjectSetInteger(0,objname,OBJPROP_ANCHOR,ANCHOR_RIGHT_LOWER);
   ObjectSetInteger(0,objname,OBJPROP_XDISTANCE,5);
   ObjectSetInteger(0,objname,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,objname,OBJPROP_COLOR,TextColor);
   ObjectSetInteger(0,objname,OBJPROP_FONTSIZE,FontSize*0.8);
   ObjectSetString(0,objname,OBJPROP_FONT,"Arial");
   ObjectSetString(0,objname,OBJPROP_TEXT,text);
}


void DeleteLegend()
{
   ObjectsDeleteAll(0,namespace+"-"+"Legend");
}


void DeleteLevels()
{
   if(DrawLevelsAllCharts)
   {
      long chartid=ChartFirst();
      while(chartid>-1)
      {
         if(ChartSymbol(chartid)==Symbol())
         {
            ObjectsDeleteAll(chartid,namespace+"-"+"Level");
            ObjectsDeleteAll(chartid,namespace+"-"+"Rectangle");
         }
         chartid=ChartNext(chartid);
      }
   }
   else
      ObjectsDeleteAll(0,namespace+"-"+"Level");
}


void DeleteText()
{
   ObjectsDeleteAll(0,namespace+"-"+"Text");
}


void DeleteAllObjects()
{
   ObjectsDeleteAll(0,namespace);
}


void OpenOrder(int type, double volume=NULL)
{
   if(type==OP_BUY)
      OpenBuy(volume);
   if(type==OP_SELL)
      OpenSell(volume);
}


void OpenBuy(double volume=NULL)
{
   double v=_OpenLots;
   if(volume!=NULL)
      v=volume;
   int ret=OrderSend(_Symbol,OP_BUY,v,Ask,5,0,0,namespace,WS.currentbasemagicnumber);
   if(ret>-1)
      WS.currentbasemagicnumber++;
   SetLastError(ret);
}


void OpenSell(double volume=NULL)
{
   double v=_OpenLots;
   if(volume!=NULL)
      v=volume;
   int ret=OrderSend(_Symbol,OP_SELL,v,Bid,5,0,0,namespace,WS.currentbasemagicnumber);
   if(ret>-1)
      WS.currentbasemagicnumber++;
   SetLastError(ret);
}


void AddPairsInTrades(string tradedsymbol)
{
   int asize=ArraySize(BI.pairsintrades);
   string symbol=StringSubstr(tradedsymbol,0,6);
   bool found=false;
   for(int i=0; i<asize; i++)
   {
      if(BI.pairsintrades[i]==symbol)
         found=true;
   }
   if(!found)
   {
      ArrayResize(BI.pairsintrades,asize+1);
      BI.pairsintrades[asize]=symbol;
   }
}


void CloseAll()
{
   while(working)
   {}
   working=true;
   CloseAllInternal();
   working=false;
}


void CloseAllInternal()
{
   int total=OrdersTotal();
   int cnt=0, delcnt=0;
   RefreshRates();
   for(cnt=total-1;cnt>=0;cnt--)
   {
      if(OrderSelect(cnt, SELECT_BY_POS, MODE_TRADES))
         if(IsOrderToManage())
            if(CloseSelectedOrder())
               delcnt++;
   }
   if(delcnt>0)
      DeleteText();
   closeallcommand=false;
}


bool CloseSelectedOrder()
{
   bool ret;
   if(OrderType()==OP_BUY)
      ret=OrderClose(OrderTicket(),OrderLots(),MarketInfo(OrderSymbol(),MODE_BID),5);
   if(OrderType()==OP_SELL) 
      ret=OrderClose(OrderTicket(),OrderLots(),MarketInfo(OrderSymbol(),MODE_ASK),5);
   if(OrderType()>OP_SELL)
      ret=OrderDelete(OrderTicket());
   SetLastErrorBool(ret);
   return ret;
}


bool IsAutoTradingEnabled()
{
   return AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)
         &&AccountInfoInteger(ACCOUNT_TRADE_EXPERT)
         &&TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)
         &&MQLInfoInteger(MQL_TRADE_ALLOWED);
}


static datetime lastctrl=0;
void OnChartEvent(const int id, const long& lparam, const double& dparam, const string& sparam)
{
   if(id==CHARTEVENT_OBJECT_CLICK)
   {
      if(StringFind(sparam,"-SymbolButton")>-1)
         SwitchSymbol(ObjectGetString(0,sparam,OBJPROP_TEXT));
   }
   
   if(id==CHARTEVENT_KEYDOWN)
   {
      if(lparam==17)
      {
         lastctrl=TimeLocal();
         DrawLevels();
         DisplayLegend();
      }
      if(TimeLocal()-lastctrl<2)
      {
         lastctrl=TimeLocal();
         if (lparam == 49)
            OpenBuy();
         if (lparam == 51)
            OpenSell();
         if (lparam == 48)
            closeallcommand=true;
         if (lparam == 56)
            SetBEClose();
         if (lparam == 54)
            SetSoftStopMode();
         if (lparam == 53)
            SetHardStopMode();
         if (lparam == 188)
            _OpenLots=MathMax(_OpenLots-0.01,0.01);
         if (lparam == 190)
            _OpenLots+=0.01;
      }
   }
}


void SwitchSymbol(string tosymbol)
{
   if(istesting)
      return;
   string currentsymbol=StringSubstr(ChartSymbol(),0,6);
   if(currentsymbol!=tosymbol)
   {
      if(SwitchSymbolClickAllCharts)
      {
         long chartid=ChartFirst();
         while(chartid>-1)
         {
            if(chartid!=ChartID())
               ChartSetSymbolPeriod(chartid,tosymbol+ExtraChars,ChartPeriod(chartid));
            chartid=ChartNext(chartid);
         }
      }
      ChartSetSymbolPeriod(0,tosymbol+ExtraChars,0);
   }
}


void SetLastErrorBool(bool result)
{
   if(!result)
      SetLastError(-1);
}


void SetLastError(int result)
{
   if(result>-1)
      return;
   lasterrortime=TimeLocal();
   lasterrorstring="Went wrong, "+ErrorDescription(GetLastError());
}
