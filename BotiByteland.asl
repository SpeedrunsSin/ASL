state("BotiByteland-Win64-Shipping"){}

startup
{
    vars.Log = (Action<object>)((output) => print("[Boti]" + output));

    if (timer.CurrentTimingMethod == TimingMethod.RealTime)
    {
        var timingMessage = MessageBox.Show(
            "This game uses RTA w/o Loads as the main timing method.\n"
            + "LiveSplit is currently set to show Real Time (RTA).\n"
            + "Would you like to set the timing method to RTA w/o Loads?",
            "Boti: Byteland Overclocker | LiveSplit",
            MessageBoxButtons.YesNo, MessageBoxIcon.Question
        );
        if (timingMessage == DialogResult.Yes)
        {
            timer.CurrentTimingMethod = TimingMethod.GameTime;
        }
    }

    // Split settings
    settings.Add("enterHub", false, "Splits when entering the hub");
    settings.Add("Leave Achi02_name_Clock_Up", false, "Level 1 -> Hub", "enterHub");
    settings.Add("Leave Achi03_name_Tripping_Down_Memory_Lane", false, "Level 2 -> Hub", "enterHub");
    settings.Add("Leave Achi04_name_Port_In_A_Storm", false, "Level 3 -> Hub", "enterHub");
    settings.Add("Leave Achi05_name_The_Show_Must_Log_On", false, "Level 4 -> Hub", "enterHub");
    settings.Add("Leave Achi06_name_Biggest_Fans", false, "Level 5 -> Hub", "enterHub");
    settings.Add("Leave Achi07_name_A_Good_Bot_Is_Hard_To_Find", false, "Level 6 -> Hub", "enterHub");
    settings.Add("Leave Achi08_name_Current_Affairs", false, "Level 7 -> Hub", "enterHub");

    settings.Add("leaveHub", false, "Splits when leaving the hub");
    settings.Add("Enter Achi02_name_Clock_Up", false, "Hub -> Level 1", "leaveHub");
    settings.Add("Enter Achi03_name_Tripping_Down_Memory_Lane", false, "Hub -> Level 2", "leaveHub");
    settings.Add("Enter Achi04_name_Port_In_A_Storm", false, "Hub -> Level 3", "leaveHub");
    settings.Add("Enter Achi05_name_The_Show_Must_Log_On", false, "Hub -> Level 4", "leaveHub");
    settings.Add("Enter Achi06_name_Biggest_Fans", false, "Hub -> Level 5", "leaveHub");
    settings.Add("Enter Achi07_name_A_Good_Bot_Is_Hard_To_Find", false, "Hub -> Level 6", "leaveHub");
    settings.Add("Enter Achi08_name_Current_Affairs", false, "Hub -> Level 7", "leaveHub");
    settings.Add("Enter Achi09_name_All_Codes_Lead_to_Home", false, "Hub -> Level 8", "leaveHub");

}

init
{
    	vars.CancelSource = new CancellationTokenSource();
	vars.ScanThread = new Thread(() =>
	{
		vars.Log("Starting scan thread.");

		var gWorld = IntPtr.Zero;
		var gWorldTrg = new SigScanTarget(10, "80 7C 24 ?? 00 ?? ?? 48 8B 3D ???????? 48")
		{ OnFound = (p, s, ptr) => ptr + 0x4 + p.ReadValue<int>(ptr) };

		var scanner = new SignatureScanner(game, modules.First().BaseAddress, modules.First().ModuleMemorySize);
		var token = vars.CancelSource.Token;

		while (!token.IsCancellationRequested)
		{
			if (gWorld == IntPtr.Zero && (gWorld = scanner.Scan(gWorldTrg)) != IntPtr.Zero)
			{
				vars.Data = new MemoryWatcherList
				{
					new MemoryWatcher<bool>(new DeepPointer(gWorld, 0x1B8, 0x529)) { Name = "bIsTransitioning"}, // Load removal
					new MemoryWatcher<bool>(new DeepPointer(gWorld, 0x1B8, 0x3B1)) { Name = "bDuringFinalCutscene"}, // End Split
					new MemoryWatcher<bool>(new DeepPointer(gWorld, 0x1B8, 0x498, 0xB0)) { Name = "bIsMenuLevel"}, // In main menu
					new MemoryWatcher<bool>(new DeepPointer(gWorld, 0x1B8, 0x498, 0xB1)) { Name = "bIsHubLevel"},  // In hub
					new MemoryWatcher<int>(new DeepPointer(gWorld, 0x1B8, 0x498, 0x50 + 0x58)) { Name = "AchievementWhenFinished"}, // Used to identify levels
				};

				vars.Log("Found GWorld at 0x" + gWorld.ToString("X") + ".");
				break;
			}

			Thread.Sleep(2000);
		}

		// TODO: Find sigscan instead
		vars.FNamePool = modules.First().BaseAddress + 0x6C21310;
		if (vars.FNamePool != IntPtr.Zero)
			vars.Log("Found FNamePool at 0x" + vars.FNamePool.ToString("X") + ".");

		vars.Log("Exiting scan thread.");
	});

	vars.ScanThread.Start();


	Func<int, string> FNameToString = (comparisonIndex) =>
	{
		if (vars.FNamePool == IntPtr.Zero)
		{
			return null;
		}

		var blockIndex = comparisonIndex >> 16;
		var blockOffset = 2 * (comparisonIndex & 0xFFFF);
		var headerPtr = new DeepPointer(vars.FNamePool + blockIndex * 8, blockOffset);

		byte[] headerBytes = null;
		if (headerPtr.DerefBytes(game, 2, out headerBytes))
		{
			bool isWide = (headerBytes[0] & 0x01) != 0;
			int length = (headerBytes[1] << 2) | ((headerBytes[0] & 0xC0) >> 6);

			IntPtr headerRawPtr;
			if (headerPtr.DerefOffsets(game, out headerRawPtr))
			{
				var stringPtr = new DeepPointer(headerRawPtr + 2);
				ReadStringType stringType = isWide ? ReadStringType.UTF16 : ReadStringType.ASCII;
				int numBytes = length * (isWide ? 2 : 1);

				string str;
				if (stringPtr.DerefString(game, stringType, numBytes, out str))
				{
					return str;
				}
			}
		}

		return null;
	};

	Func<string, string> GetObjectNameFromObjectPath = (objectPath) =>
	{
		if (objectPath == null)
		{
			return null;
		}

		int lastDotIndex = objectPath.LastIndexOf('.');
		if (lastDotIndex == -1)
		{
			return objectPath;
		}

		return objectPath.Substring(lastDotIndex + 1);
	};

	Func<int, string> GetObjectNameFromFName = (comparisonIndex) =>
	{
		return GetObjectNameFromObjectPath(FNameToString(comparisonIndex));
	};
	vars.GetObjectNameFromFName = GetObjectNameFromFName;
}

update
{
    if (vars.ScanThread.IsAlive) return false;

    vars.Data.UpdateAll(game);

    if (vars.Data["bIsTransitioning"].Changed)
        vars.Log("bIsTransitioning: " + vars.Data["bIsTransitioning"].Current);

    if (vars.Data["bDuringFinalCutscene"].Changed)
        vars.Log("bDuringFinalCutscene: " + vars.Data["bDuringFinalCutscene"].Current);

    if (vars.Data["bIsMenuLevel"].Changed)
        vars.Log("bIsMenuLevel: " + vars.Data["bIsMenuLevel"].Current);

    if (vars.Data["bIsHubLevel"].Changed)
        vars.Log("bIsHubLevel: " + vars.Data["bIsHubLevel"].Current);

    current.AchiName = vars.GetObjectNameFromFName(vars.Data["AchievementWhenFinished"].Current);
    if (vars.Data["AchievementWhenFinished"].Changed)
    {
        vars.Log("Old AchievementWhenFinished: " + old.AchiName);
        vars.Log("Current AchievementWhenFinished: " + current.AchiName);
    }
        
}

isLoading
{
    return vars.Data["bIsMenuLevel"].Current || vars.Data["bIsTransitioning"].Current;
}

start
{
    return !vars.Data["bIsMenuLevel"].Current && vars.Data["bIsMenuLevel"].Old;
}

split
{
    // Final Split
    if (vars.Data["bDuringFinalCutscene"].Changed && vars.Data["bDuringFinalCutscene"].Current)
    { 
        return true;
    }

    // Level Splits
    if (vars.Data["AchievementWhenFinished"].Changed)
    {
        if (current.AchiName == "None") 
        {
            return settings["Leave " + old.AchiName];
        }

        if (old.AchiName == "None")
        {
            return settings["Enter " + current.AchiName];
        }
    }   
}

