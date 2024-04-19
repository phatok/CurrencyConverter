unit uMain;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  System.Net.URLClient, System.Net.HttpClient, System.Net.HttpClientComponent,
  FMX.StdCtrls, FMX.Controls.Presentation, FMX.Edit, FMX.ListBox,
  JSON, IOUtils, FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.Stan.Error,
  FireDAC.UI.Intf, FireDAC.Phys.Intf, FireDAC.Stan.Def, FireDAC.Stan.Pool,
  FireDAC.Stan.Async, FireDAC.Phys, FireDAC.FMXUI.Wait, FireDAC.Stan.Param,
  FireDAC.DatS, FireDAC.DApt.Intf, FireDAC.DApt, FireDAC.Comp.Client, Data.DB,
  FireDAC.Comp.DataSet, FireDAC.Stan.ExprFuncs, FireDAC.Phys.SQLiteWrapper.Stat,
  FireDAC.Phys.SQLiteDef, FireDAC.Phys.SQLite;

type
  TfMain = class(TForm)
    cbSrcCurrency: TComboBox;
    cbDstCurrency: TComboBox;
    edValue: TEdit;
    HTTP: TNetHTTPClient;
    FDConnection: TFDConnection;
    FDQuery: TFDQuery;
    FDTable: TFDTable;
    FDPhysSQLiteDriverLink: TFDPhysSQLiteDriverLink;
    UpdateTimer: TTimer;
    lbResult: TLabel;
    procedure LoadCurrencyRates;
    procedure CreateConnectSQLTable;
    procedure Calculate;
    procedure AddLineToLog(Str : string);
    procedure cbSrcCurrencyChange(Sender: TObject);
    procedure edValueChangeTracking(Sender: TObject);
    procedure cbDstCurrencyChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure UpdateTimerTimer(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

  TCurrencyRate = class(TObject)
    Code : string;
    Value : double;
  end;

var
  fMain: TfMain;

const
  CurrencyExchangeJSONURL = 'https://www.floatrates.com/daily/eur.json';
  DBName = 'curr_exchange.sqlite';
  TableName = 'History';

implementation

{$R *.fmx}

procedure TfMain.FormCreate(Sender: TObject);
var CurrencyRate : TCurrencyRate;
begin
  AddLineToLog('Starting application');
  CreateConnectSQLTable;
  LoadCurrencyRates;
  UpdateTimer.Enabled := true;

   //adding main currency - EURO
  CurrencyRate := TCurrencyRate.Create;
  CurrencyRate.Code := 'EUR';
  CurrencyRate.Value := 1.0;
  cbSrcCurrency.Items.AddObject('EUR' + ' - ' + 'Euro', CurrencyRate);
  cbDstCurrency.Items.AddObject('EUR' + ' - ' + 'Euro', CurrencyRate);
end;

procedure TfMain.AddLineToLog(Str: string);
begin
 TThread.Synchronize(nil,
  procedure
  begin
    TFile.AppendAllText(TPath.Combine(TPath.GetDocumentsPath, 'logfile.txt'),
                        '[' + DateTimeToStr(Now) + ']'#9 + Str + #13#10);
  end);
end;

procedure TfMain.Calculate;
var InValue, EURValue, ResultValue, SrcCurrencyRate, DstCurrencyRate : Double;
    SrcCurrencyCode, DstCurrencyCode : string;
begin
  try
    //if input value is empty or space(s) - nothing to do - exit
    if Trim(edValue.Text) = '' then
    begin
      lbResult.Text := 'Input value is empty';
      exit;
    end;

    //if one of comboboxes doesnt have selected value - exit
    if ((cbSrcCurrency.Selected = Nil) or (cbDstCurrency.Selected = Nil)) then
    begin
      lbResult.Text := 'You need to select currencies pair';
      Exit;
    end;

    //if error with conversion - exit
    try
      InValue := edValue.Text.ToDouble;
    except
      lbResult.Text := 'Input value is not numeric';
      exit;
    end;

    //filling vars from selected comboboxes
    SrcCurrencyCode := TCurrencyRate(cbSrcCurrency.Selected.Data).Code;
    SrcCurrencyRate := TCurrencyRate(cbSrcCurrency.Selected.Data).Value;
    DstCurrencyCode := TCurrencyRate(cbDstCurrency.Selected.Data).Code;
    DstCurrencyRate := TCurrencyRate(cbDstCurrency.Selected.Data).Value;

    //calculations, based on main currecny - Euro
    EURValue := InValue / SrcCurrencyRate;
    ResultValue := EURValue * DstCurrencyRate;

    //show result
    lbResult.Text :=  Trim(edValue.Text) + ' ' + SrcCurrencyCode +
                      ' = ' +
                      FormatFloat('0.##', ResultValue) + ' ' + DstCurrencyCode;

    //Inserting row to table
    //TimeStamp|FromCurrency|FromCurrencyRate|ToCurrency|ToCurrencyRate|InputValue|Result
    AddLineToLog('Inserting data to table:');
    AddLineToLog('InputValue = ' + edValue.Text);
    AddLineToLog('SrcCurrencyCode = ' + SrcCurrencyCode);
    AddLineToLog('SrcCurrencyRate = ' + SrcCurrencyRate.ToString);
    AddLineToLog('DstCurrencyCode = ' + DstCurrencyCode);
    AddLineToLog('DstCurrencyRate = ' + DstCurrencyRate.ToString);
    AddLineToLog('ResultValue = ' + ResultValue.ToString);

    FDTable.InsertRecord([now, SrcCurrencyCode, SrcCurrencyRate, DstCurrencyCode, DstCurrencyRate, InValue, ResultValue]);
    FDConnection.Commit;
    AddLineToLog('Ok');

  except
    on E: Exception do
      AddLineToLog('ERROR ' + E.Message);
  end;
end;

procedure TfMain.CreateConnectSQLTable;
begin
  try
    AddLineToLog('Establishing db and table connection');

    //setting up db connection
    FDConnection.Connected:= False;
    FDConnection.Params.Values['database'] := DBName;
    FDConnection.LoginPrompt := False;
    FDConnection.DriverName := 'SQLite';
    FDConnection.Connected:= True;

    //creating(or not if it already exists) table using SQL query
    FDQuery.Connection := FDConnection;
    FDQuery.SQL.Text :=
      'CREATE TABLE IF NOT EXISTS ' + TableName + '  (' +
      'TimeStamp datetime PRIMARY KEY, ' +
      'FromCurrency NVARCHAR(16) NOT NULL, ' +
      'FromCurrencyRate float NOT NULL, ' +
      'ToCurrency NVARCHAR(16) NOT NULL, ' +
      'ToCurrencyRate float NOT NULL, ' +
      'InputValue float NOT NULL, ' +
      'ResultValue float NOT NULL' +
      ');';
    FDQuery.ExecSQL;

    //connect table to TFDTable component
    FDTable.Connection := FDConnection;
    FDTable.Fields.Clear;
    FDTable.TableName := TableName;
    FDTable.Open();

    AddLineToLog('Ok');

  except
    on E: Exception do
      AddLineToLog('ERROR ' + E.Message);
  end;
end;

procedure TfMain.LoadCurrencyRates;
begin
  //Loading data in separate thread to avoid main UI thread lock
  TThread.CreateAnonymousThread(
    procedure
    var JSONData, VisibleCurrencyName, cCode: String;
        cValue : double;
        JSONObject : TJSONObject;
        JSONPair : TJSONPair;
        CurrencyRate : TCurrencyRate;
    begin
      try
        HTTP.ConnectionTimeout := 3000; //3 sec
        HTTP.ResponseTimeout := 3000;
        HTTP.SendTimeout := 3000;
        HTTP.Asynchronous := false;
        AddLineToLog('Dowloading JSON');

        //downloading and parsing JSON
        try
          JSONData := HTTP.Get(CurrencyExchangeJSONURL).ContentAsString;
        except
          raise Exception.Create('Could not download JSON');
        end;
        AddLineToLog('Ok');

        AddLineToLog('Parsing JSON');
        JSONObject := TJSonObject.ParseJSONValue(JSONData) as TJSONObject;
        AddLineToLog('Ok');

        AddLineToLog('Filling comboboxes');
        try
          for JSONPair in JSONObject do
          begin
            cCode := (JSONPair.JsonValue).GetValue<string>('alphaCode');
            cValue := (JSONPair.JsonValue).GetValue<double>('rate');
            VisibleCurrencyName := (JSONPair.JsonValue).GetValue<string>('alphaCode') + ' - ' + (JSONPair.JsonValue).GetValue<string>('name');

            //adding/updating item to listboxes in main UI thread
            TThread.Synchronize(nil,
              procedure
              var i : integer;
                  found : boolean;
              begin
                found := false;
                for i := 0 to cbSrcCurrency.Items.Count-1 do
                begin
                  //found - just update Value
                  if TCurrencyRate(cbSrcCurrency.Items.Objects[i]).Code = cCode then
                  begin
                    TCurrencyRate(cbSrcCurrency.Items.Objects[i]).Value := cValue;
                    found := true;
                    break;
                  end;
                end;

                //not found - create/add
                if not found then
                begin
                  CurrencyRate := TCurrencyRate.Create;
                  CurrencyRate.Code := cCode;
                  CurrencyRate.Value := cValue;

                  cbSrcCurrency.Items.AddObject(VisibleCurrencyName, CurrencyRate);
                  cbDstCurrency.Items.AddObject(VisibleCurrencyName, CurrencyRate);
                end;

              end);
          end;

          //calculate result value and enable comboboxes for the first time
          TThread.Synchronize(nil,
            procedure
            begin
              Calculate;
              if not cbSrcCurrency.Enabled then cbSrcCurrency.Enabled := true;
              if not cbDstCurrency.Enabled then cbDstCurrency.Enabled := true;
            end);

          AddLineToLog('Ok');
        finally
          JSONObject.Free;
        end;

      except
        on E: Exception do
          begin
            lbResult.Text := 'Unable to load currency rates';
            AddLineToLog('ERROR ' + E.Message);
          end;
      end;

    end).Start;
end;

procedure TfMain.UpdateTimerTimer(Sender: TObject);
begin
  LoadCurrencyRates;
end;

procedure TfMain.edValueChangeTracking(Sender: TObject);
begin
  Calculate;
end;

procedure TfMain.cbDstCurrencyChange(Sender: TObject);
begin
  Calculate;
end;

procedure TfMain.cbSrcCurrencyChange(Sender: TObject);
begin
  Calculate;
end;

procedure TfMain.FormClose(Sender: TObject; var Action: TCloseAction);
var i : integer;
begin
  //closing connection to db and freeing dynamically created objects
  FDConnection.Close;
  for i := 0 to cbSrcCurrency.Items.Count-1 do
  begin
    cbSrcCurrency.Items.Objects[i].Free;
  end;
end;


end.
