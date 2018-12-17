//C = Confidentiality (Vehicles only receive messages intended for them)
//I = Integrity (The contents of the received message are the same as when it was sent)
//A = Availability (CAM messages are sent on time and arrive within some time bound)

//Cooperative Awareness Messages (CAM) generation for vehicle j.
//These are used to inform other vehicles of the current vehicle's state
//CAM messages are intended for all that receive them so proving Confidentiality is unnecessary


datatype CAM = CAM(id:int,seqno:int, time:int, heading:int, speed:int, position:int)
//Main method to get everything going

// Min and Max CAM generation times in ms
const T_GenCamMin := 100;
const T_GenCamMax := 1000;

const N_GenCamMax := 3;
const N_GenCamDefault := N_GenCamMax;

// Thresholds
const headingthreshold := 4;
const speedthreshold := 4;
const posthreshold := 0.5 as real;

const MaxMsgs := 100; // Max number of messages to verify for

method Main()
{
  var carNo := 10;
  var SleepInterval := 3;
  var TxInterval := 5;
  var c := 0;
  
  //for receive
  
  var prev := new CAM [3];
  prev[0] := CAM(1,0,1,2,3,4);//for testing
  prev[1] := CAM(1,1,2,3,4,5);
  prev[2] := CAM(1,2,3,4,5,6);

  while(c<carNo)
  decreases carNo - c;
  {
     //var res := sendCAM(SleepInterval, TxInterval,c);
     c:= c+1;  
     //print res; 
  }
  
}
method sendCAM(T_CheckCamGen:int, T_GenCam_DCC:int, j: int) returns (msgs:seq<CAM>, now:int)
  requires 0 < T_CheckCamGen <= T_GenCamMin;
  requires T_GenCamMin <= T_GenCam_DCC <= T_GenCamMax;

  ensures T_GenCam_DCC * |msgs| <= now <= T_GenCamMax * |msgs|;
  ensures |msgs| >= 2 ==> forall i: int :: 1 <= i < |msgs| ==> T_GenCam_DCC <= (msgs[i].time - msgs[i-1].time) <= T_GenCamMax;
  ensures |msgs| == MaxMsgs;
{
  var T_GenCam := T_GenCamMax; // currently valid upper limit of the CAM generation interval
  var T_GenCamNext := T_GenCam;
  var N_GenCam := N_GenCamDefault;
  var trigger_two_count := 0;
  
  now := 0;
  var LastBroadcast, PrevLastBroadcast := now, now;

  var heading, speed, pos := GetHeading(now), GetSpeed(now), GetPosition(now);
  var prevheading, prevspeed, prevpos, statechanged := -1, -1, -1, false;

  var seqno := 0;
  msgs := [];
  var prevsent := msgs;

  while (|msgs| < MaxMsgs)
  decreases MaxMsgs - |msgs|;
  invariant 0 <= |msgs| <= MaxMsgs;

  // Check variables remain within valid ranges
  invariant 0 < N_GenCam <= N_GenCamMax;
  invariant T_GenCamMin <= T_GenCamNext <= T_GenCamMax;
  invariant T_GenCamMin <= T_GenCam <= T_GenCamMax;

  invariant 0 <= PrevLastBroadcast <= now;
  invariant now == LastBroadcast;
  invariant now - T_GenCamMax <= PrevLastBroadcast <= LastBroadcast;  

  // Check that messages are sent often enough
  invariant |msgs| >= 1 ==> msgs[|msgs|-1].time == LastBroadcast;
  invariant |msgs| >= 2 ==> msgs[|msgs|-2].time == PrevLastBroadcast;

  invariant now > 0 ==> T_GenCam_DCC <= LastBroadcast - PrevLastBroadcast <= T_GenCamMax;
  
  // Message sent conditions (don't test when entering the loop)
  invariant now > 0 ==> CAM(j,seqno,now,heading,speed,pos) in msgs;
  invariant now > 0 ==> |prevsent| + 1 == |msgs|;

  invariant |msgs| >= 2 ==> forall i: int :: 1 <= i < |msgs| ==> T_GenCam_DCC <= (msgs[i].time - msgs[i-1].time) <= T_GenCamMax;

  invariant T_GenCamMin * |msgs| <= T_GenCam_DCC * |msgs| <= now;
  invariant now > 0 ==> now <= T_GenCamMax * |msgs|;
  {
    prevsent, PrevLastBroadcast := msgs, LastBroadcast;
    T_GenCam := T_GenCamNext;
    statechanged := false;

    // Advance time to the earliest a CAM can be sent (T_CamGen_DCC used as congestion control)
    now := now + T_GenCam_DCC;

    // Find the time at which information has changed or we have waited T_GenCam
    while (true)
    decreases LastBroadcast + T_GenCam - now;
    invariant now - LastBroadcast <= max(T_GenCam_DCC, T_GenCam);
    {
        // Get vehicle information
        heading, speed, pos := GetHeading(now), GetSpeed(now), GetPosition(now);
      
        // Check if this information has changed
        statechanged := abs(heading - prevheading) >= headingthreshold ||
                        abs(speed - prevspeed) >= speedthreshold ||
                        abs(pos - prevpos) >= posthreshold.Floor;
        
        if (statechanged || now - LastBroadcast >= T_GenCam)
        {
            break; // Don't sleep if we need to send a CAM
        }
        else
        {
            now := now + T_CheckCamGen; // Sleep for a bit to advance time
        }
    }

    assert LastBroadcast + T_GenCam_DCC <= now <= LastBroadcast + T_GenCamMax;
    
    seqno := (seqno + 1) % 256;
    msgs := msgs + [CAM(j,seqno,now,heading,speed,pos)];
    
    if (statechanged) { // Trigger 1
      T_GenCamNext := now - LastBroadcast;
      trigger_two_count := 0; // Reset
    }
    else if (now - LastBroadcast >= T_GenCam){ // Trigger 2
      trigger_two_count := trigger_two_count + 1;
      if (trigger_two_count == N_GenCam) {
        T_GenCamNext := T_GenCamMax;
      }
    }

    // Set current values as old values
    LastBroadcast := now;
    prevheading, prevspeed, prevpos := heading, speed, pos;
  }
  return msgs, now;
}
method receiveCAM(fromid:int, cams:seq<CAM>) returns ()
requires 0 <= fromid < |cams|;
requires fromid == cams[fromid].id;  //To check that the vehicle the message claims it was sent from was actually sent from that vehicle.
{
  var now := Now();
  if(Sign(Magnitude(cams[fromid].heading)) == - Sign(Magnitude(GetHeading(now))))
  {
    //Ignore cars travelling in the opposite direction to us
  }
 var speeddiff := GetSpeed(now) - cams[fromid].speed;

 //Negative speeddiff indicates that we are getting closer to the vehicle ahead of us so we may need to brake
 if (speeddiff < 0){
     var deceleration := Brake(cams[fromid].speed);
     var newspeed := cams[fromid].speed - deceleration;
  }
 
}

//helper functions and methods are below

method Now() returns(n:int)
{
  //returns the current time
}

function method GetHeading(now: int) :int
{
  20
}

function method GetSpeed(now: int):int
{
  50
}

function method GetPosition(now: int):int
{
  10
}

function method abs(x: int): int
{
   if x < 0 then -x else x
}


method Sleep(SleepInterval:int) returns ()
{}


function method hasOverflowed(s1:int, s2:int): bool{
  s1>s2
}

function method Sign(magnitude:int):int{
  magnitude
}

function method Magnitude(heading:int):int{
  heading
}

method Brake(s:int)  returns (deceleration:int)
ensures 0<= deceleration <= 10; // 10 should be 9.81 but left it as 10 so that I could use ints for simplicity 
{ 
  deceleration := 8;

}
function method max(x: int, y: int): int
{
  if x < y then y else x
}

 
method sqrt (s:int) returns (r:int)
requires s >= 0;
ensures 0 <= r * r && r*r <= s && s < (r+1)*(r+1); 
{
  r := 0 ;
  while ((r+1) * (r+1) <= s)
  decreases s - (r+1) * (r+1);
  invariant r*r <= s ;
  {
    r := r+1 ;
  }
}