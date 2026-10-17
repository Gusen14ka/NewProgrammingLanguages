with Ada.Text_IO;            use Ada.Text_IO;
with Ada.Real_Time;          use Ada.Real_Time;
with Ada.Command_Line;
with Ada.Float_Text_IO;
with Ada.Numerics.Discrete_Random;
with Ada.Unchecked_Deallocation;

procedure Main is

   type Int_Array is array (Positive range <>) of Integer;
   type Int_Array_Access is access Int_Array;
   procedure Free is new Ada.Unchecked_Deallocation (Int_Array, Int_Array_Access);

   N         : Positive := 2_000_000;
   Max_Depth : Natural  := 3;
   Threshold : constant := 10_000;

   Data, Tmp : Int_Array_Access;

   procedure Merge (Lo, Mid, Hi : Positive) is
      I : Positive := Lo;
      J : Positive := Mid + 1;
      K : Positive := Lo;
   begin
      while I <= Mid and J <= Hi loop
         if Data (I) <= Data (J) then
            Tmp (K) := Data (I); I := I + 1;
         else
            Tmp (K) := Data (J); J := J + 1;
         end if;
         K := K + 1;
      end loop;
      while I <= Mid loop
         Tmp (K) := Data (I); I := I + 1; K := K + 1;
      end loop;
      while J <= Hi loop
         Tmp (K) := Data (J); J := J + 1; K := K + 1;
      end loop;
      Data (Lo .. Hi) := Tmp (Lo .. Hi);
   end Merge;

   procedure Seq_Sort (Lo, Hi : Positive) is
      Mid : Positive;
   begin
      if Lo >= Hi then
         return;
      end if;
      Mid := (Lo + Hi) / 2;
      Seq_Sort (Lo, Mid);
      Seq_Sort (Mid + 1, Hi);
      Merge (Lo, Mid, Hi);
   end Seq_Sort;

   procedure Par_Sort (Lo, Hi : Positive; Depth : Natural);

   task type Sorter is
      entry Start (Lo, Hi : Positive; Depth : Natural);
      entry Finish;
   end Sorter;

   task body Sorter is
      My_Lo, My_Hi : Positive;
      My_Depth     : Natural;
   begin
      accept Start (Lo, Hi : Positive; Depth : Natural) do
         My_Lo := Lo; My_Hi := Hi; My_Depth := Depth;
      end Start;
      Par_Sort (My_Lo, My_Hi, My_Depth);
      accept Finish;
   end Sorter;

   procedure Par_Sort (Lo, Hi : Positive; Depth : Natural) is
      Mid : Positive;
   begin
      if Depth = 0 or else Hi - Lo < Threshold then
         Seq_Sort (Lo, Hi);
         return;
      end if;
      Mid := (Lo + Hi) / 2;
      declare
         Left : Sorter;
      begin
         Left.Start (Lo, Mid, Depth - 1);
         Par_Sort (Mid + 1, Hi, Depth - 1);
         Left.Finish;
      end;
      Merge (Lo, Mid, Hi);
   end Par_Sort;

   function Is_Sorted return Boolean is
   begin
      for I in Data'First .. Data'Last - 1 loop
         if Data (I) > Data (I + 1) then
            return False;
         end if;
      end loop;
      return True;
   end Is_Sorted;

   package Rand is new Ada.Numerics.Discrete_Random (Integer);
   Gen : Rand.Generator;

   Original : Int_Array_Access;
   T0       : Time;
   Seq_Ms, Par_Ms : Duration;

begin
   if Ada.Command_Line.Argument_Count >= 1 then
      N := Positive'Value (Ada.Command_Line.Argument (1));
   end if;
   if Ada.Command_Line.Argument_Count >= 2 then
      Max_Depth := Natural'Value (Ada.Command_Line.Argument (2));
   end if;

   Rand.Reset (Gen, 42);
   Original := new Int_Array (1 .. N);
   for I in Original'Range loop
      Original (I) := Rand.Random (Gen) mod 1_000_000;
   end loop;

   Data := new Int_Array'(Original.all);
   Tmp  := new Int_Array (1 .. N);

   Put_Line ("Elements: " & N'Image & ", parallel depth: " & Max_Depth'Image
             & " (up to" & Natural'Image (2 ** Max_Depth) & " tasks)");

   T0 := Clock;
   Seq_Sort (1, N);
   Seq_Ms := To_Duration (Clock - T0) * 1000;
   Put_Line ("Sequential: " & Integer'Image (Integer (Seq_Ms)) & " ms, sorted = "
             & Boolean'Image (Is_Sorted));

   Data.all := Original.all;
   T0 := Clock;
   Par_Sort (1, N, Max_Depth);
   Par_Ms := To_Duration (Clock - T0) * 1000;
   Put_Line ("Parallel:   " & Integer'Image (Integer (Par_Ms)) & " ms, sorted = "
             & Boolean'Image (Is_Sorted));

   if Par_Ms > 0.0 then
      Put ("Speedup:    x");
      Ada.Float_Text_IO.Put (Float (Seq_Ms / Par_Ms), Fore => 1, Aft => 2, Exp => 0);
      New_Line;
   end if;

   if N <= 30 then
      for I in Data'Range loop
         Put (Data (I)'Image);
      end loop;
      New_Line;
   end if;

   Free (Data); Free (Tmp); Free (Original);
end Main;
