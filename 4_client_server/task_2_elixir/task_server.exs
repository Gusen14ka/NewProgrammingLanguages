defmodule Jobs do
  def run("fib " <> n), do: with_int(n, fn n -> fib(n, 0, 1) end)
  def run("factor " <> n), do: with_int(n, fn n -> factor(n, 2, []) |> Enum.join(" * ") end)
  def run("primes " <> n), do: with_int(n, &count_primes/1)

  def run("sort " <> list) do
    nums = String.split(list) |> Enum.map(&Integer.parse/1)
    if Enum.all?(nums, &match?({_, ""}, &1)),
      do: nums |> Enum.map(&elem(&1, 0)) |> Enum.sort() |> Enum.join(" "),
      else: "error: sort expects integers"
  end

  def run("sleep " <> ms), do: with_int(ms, fn ms -> Process.sleep(ms); "slept #{ms} ms" end)
  def run(other), do: "error: unknown command '#{other}' (fib N | factor N | primes N | sort a b c | sleep MS)"

  defp with_int(text, fun) do
    case Integer.parse(String.trim(text)) do
      {n, ""} when n >= 0 and n <= 1_000_000_000 -> to_string(fun.(n))
      _ -> "error: '#{text}' is not a valid number"
    end
  end

  defp fib(0, a, _), do: a
  defp fib(n, a, b), do: fib(n - 1, b, a + b)

  defp factor(n, _, acc) when n < 2, do: if(acc == [], do: [n], else: Enum.reverse(acc))
  defp factor(n, d, acc) when d * d > n, do: Enum.reverse([n | acc])
  defp factor(n, d, acc) when rem(n, d) == 0, do: factor(div(n, d), d, [d | acc])
  defp factor(n, d, acc), do: factor(n, d + 1, acc)

  defp count_primes(n), do: Enum.count(2..max(n, 2)//1, &prime?/1) - if(n < 2, do: 1, else: 0)
  defp prime?(n), do: Enum.all?(2..trunc(:math.sqrt(n))//1, &(rem(n, &1) != 0))
end

defmodule Dispatcher do
  def start(workers) do
    pid = spawn(fn -> loop(%{queue: :queue.new(), idle: [], next_id: 1}) end)
    for i <- 1..workers, do: spawn(fn -> worker(pid, i) end)
    pid
  end

  defp worker(dispatcher, num) do
    send(dispatcher, {:idle, self(), num})
    receive do
      {:job, id, client, command} ->
        result = Jobs.run(command)
        send(client, {:result, id, result})
        IO.puts("[worker #{num}] done job #{id}: #{command}")
        worker(dispatcher, num)
    end
  end

  defp loop(state) do
    receive do
      {:submit, client, command} ->
        id = state.next_id
        IO.puts("[dispatcher] job #{id} queued: #{command}")
        send(client, {:accepted, id, command})
        loop(dispatch(%{state | queue: :queue.in({id, client, command}, state.queue), next_id: id + 1}))

      {:idle, worker, num} ->
        loop(dispatch(%{state | idle: [{worker, num} | state.idle]}))
    end
  end

  defp dispatch(%{idle: [{worker, num} | rest]} = state) do
    case :queue.out(state.queue) do
      {{:value, {id, client, command}}, queue} ->
        IO.puts("[dispatcher] job #{id} -> worker #{num}")
        send(worker, {:job, id, client, command})
        dispatch(%{state | idle: rest, queue: queue})

      {:empty, _} ->
        state
    end
  end

  defp dispatch(state), do: state
end

defmodule Server do
  def start(port, workers) do
    dispatcher = Dispatcher.start(workers)
    {:ok, listen} = :gen_tcp.listen(port, [:binary, packet: :line, active: false, reuseaddr: true])
    IO.puts("Task server on port #{port}, #{workers} workers")
    accept(listen, dispatcher)
  end

  defp accept(listen, dispatcher) do
    {:ok, socket} = :gen_tcp.accept(listen)
    pid = spawn(fn -> receive do: (:go -> session(socket, dispatcher)) end)
    :ok = :gen_tcp.controlling_process(socket, pid)
    send(pid, :go)
    accept(listen, dispatcher)
  end

  defp session(socket, dispatcher) do
    :inet.setopts(socket, active: true)
    {:ok, {addr, port}} = :inet.peername(socket)
    IO.puts("[server] client #{:inet.ntoa(addr)}:#{port} connected")
    session_loop(socket, dispatcher)
  end

  defp session_loop(socket, dispatcher) do
    receive do
      {:tcp, ^socket, line} ->
        case String.trim(line) do
          "" -> :ok
          command -> send(dispatcher, {:submit, self(), command})
        end
        session_loop(socket, dispatcher)

      {:accepted, id, command} ->
        :gen_tcp.send(socket, "accepted job #{id}: #{command}\n")
        session_loop(socket, dispatcher)

      {:result, id, result} ->
        :gen_tcp.send(socket, "result of job #{id}: #{result}\n")
        session_loop(socket, dispatcher)

      {:tcp_closed, ^socket} ->
        IO.puts("[server] client disconnected")
    end
  end
end

defmodule Client do
  def start(host, port) do
    {:ok, socket} = :gen_tcp.connect(String.to_charlist(host), port, [:binary, packet: :line, active: true])
    IO.puts("Connected. Commands: fib N | factor N | primes N | sort a b c | sleep MS")
    main = self()
    spawn(fn -> read_input(main) end)
    loop(socket, 0, 0, false)
  end

  defp read_input(main) do
    case IO.gets("") do
      :eof -> send(main, :eof)
      line -> send(main, {:input, String.trim(line)}); read_input(main)
    end
  end

  defp loop(socket, sent, done, eof) do
    if eof and done == sent do
      :gen_tcp.close(socket)
    else
      receive do
        {:input, ""} -> loop(socket, sent, done, eof)
        {:input, line} -> :gen_tcp.send(socket, line <> "\n"); loop(socket, sent + 1, done, eof)
        :eof -> loop(socket, sent, done, true)
        {:tcp, ^socket, "result" <> _ = text} -> IO.write(text); loop(socket, sent, done + 1, eof)
        {:tcp, ^socket, text} -> IO.write(text); loop(socket, sent, done, eof)
        {:tcp_closed, ^socket} -> IO.puts("Server closed the connection")
      end
    end
  end
end

case System.argv() do
  ["server" | rest] ->
    port = rest |> Enum.at(0, "7979") |> String.to_integer()
    workers = rest |> Enum.at(1, "3") |> String.to_integer()
    Server.start(port, workers)

  ["client" | rest] ->
    Client.start(Enum.at(rest, 0, "127.0.0.1"), rest |> Enum.at(1, "7979") |> String.to_integer())

  _ ->
    IO.puts("Usage: elixir task_server.exs server [port] [workers] | client [host] [port]")
end
