defmodule Tmnt do
  @moduledoc """
  Documentation for Tmnt.
  """

  use Textophile, timeout: :timer.seconds(30)
  defstruct count: 0, user: nil

  def init([]) do
    #setup_shell
    IO.write(IO.ANSI.clear())
    IO.write(IO.ANSI.home())
    user = Tmnt.Login.run([])

    gl = Process.group_leader()
    :io.setopts(gl, binary: true, coding: :unicode)
    commands = ['exit', 'whoami', 'countdown']
    :io.setopts(gl, expand_fun: &expand(&1, commands))

    {:ok, %__MODULE__{user: user}}
  end

  def handle_prompt(context) do
    "#{command_count(context)}> "
  end

  def handle_command(command, context) do
    case OptionParser.split(command) do
      [main_command | args] ->
        run_command(main_command, args, context)
        |> handle_result()
      [] ->
        {:ok, context}
    end
  end

  defp increase_command_count(%{count: count} = context) do
    %{context | count: count + 1}
  end

  defp command_count(%{count: count}) do
    count
  end

  defp run_command("exit", _, context) do
    IO.puts "bye"
    {:exit, :ok, context}
  end

  defp run_command("whoami", _, %{user: user} = context) do
    user
    |> Tmnt.Login.User.name()
    |> IO.puts()
    {:ok, context}
  end

  defp run_command("countdown", args, context) do
    {[count: count], [], []} = OptionParser.parse(args, strict: [count: :integer])

    count(count, context)
  end

  defp run_command(_, _, context) do
    IO.puts "Unknown Command"
    {:ok, context}
  end

  def handle_result({:ok, context}) do
    {:ok, increase_command_count(context)}
  end

  def handle_result({:exit, _}) do
    Process.sleep :timer.seconds(2)
    run([])
  end

  def count(0, context) do
    IO.puts("0")
    {:ok, context}
  end

  def count(count, context) do
    IO.write("#{count} \r")

    Process.sleep(1000)
    count(count - 1, context)
  end

  @spec expand(charlist, [charlist]) :: {:yes | :no, to_insert :: charlist, possibilities :: [charlist]}
  def expand(current_typing, commands) do
    prefix = Enum.reverse(current_typing)
    matching_commands = Enum.filter(commands, &List.starts_with?(&1, prefix))

    {:yes, '', matching_commands}
  end
end
