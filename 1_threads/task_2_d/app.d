import core.sync.mutex : Mutex;
import core.thread : Thread;
import std.conv : to;
import std.datetime.stopwatch : StopWatch, AutoStart;
import std.math : PI, abs;
import std.random : Random, uniform, unpredictableSeed;
import std.stdio : writefln;

__gshared ulong totalInside;
__gshared Mutex lock;

void worker(ulong points, uint seed)
{
    auto rng = Random(seed);
    ulong inside = 0;
    foreach (_; 0 .. points)
    {
        immutable x = uniform(-1.0, 1.0, rng);
        immutable y = uniform(-1.0, 1.0, rng);
        if (x * x + y * y <= 1.0)
            ++inside;
    }
    lock.lock();
    totalInside += inside;
    lock.unlock();
}

void delegate() makeWorker(ulong points, uint seed)
{
    return () => worker(points, seed);
}

void main(string[] args)
{
    ulong total = args.length > 1 ? args[1].to!ulong : 40_000_000;
    lock = new Mutex;

    writefln("Points: %s", total);
    writefln("%8s %12s %12s %10s", "threads", "pi", "error", "time, ms");

    foreach (threadCount; [1, 2, 4, 8])
    {
        totalInside = 0;
        immutable perThread = total / threadCount;
        auto sw = StopWatch(AutoStart.yes);

        Thread[] threads;
        foreach (i; 0 .. threadCount)
        {
            auto t = new Thread(makeWorker(perThread, unpredictableSeed));
            t.start();
            threads ~= t;
        }
        foreach (t; threads)
            t.join();

        sw.stop();
        immutable pi = 4.0 * totalInside / (perThread * threadCount);
        writefln("%8d %12.7f %12.7f %10d", threadCount, pi, abs(pi - PI), sw.peek.total!"msecs");
    }
}
