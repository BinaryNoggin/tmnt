defmodule Textophile do
  @moduledoc """
  An OTP behaviour for creating interactive shell commands

  The behaviour is used to create commands that ask the user
  for input and then respond to those inputs.

  # Callbacks that are required:

  * c:init/1
  * c:handle_prompt/1 (optional)
  * c:handle_command/2


  # Examples

       defmodule MyCommand do
         use Textophile

         def init(stack) do
           {:ok, stack}
         end

         def handle_command(<<"push ", value::binary()>>, stack) do
           {:ok, [value | stack]}
         end

         def handle_command("pop", [head | stack]) do
           IO.puts(head)
           {:ok, stack}
         end

        def handle_command("exit", stack) do
          {:exit, :ok, stack}
        end

        def handle_prompt([]) do
          "empty>"
        end

        def handle_prompt(stack) do
          to_string(length(stack)) <> ">"
        end
      end

      MyCommand.run([1])

  # `use` can take a few options

  * :timeout - default 30 seconds
  * :input_type - default :visible
  * :prompt - default is empty and can be used instead of implementing c:handle_prompt
  """

  require Logger

  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do
      @behaviour Textophile

      def run(args) do
        options = unquote(Macro.escape(opts))
        input_type = Keyword.get(options, :input_type, :visible)
        timeout = Keyword.get(options, :timeout, :timer.seconds(30))
        Textophile.run(__MODULE__, args, timeout: timeout, input_type: input_type)
      end

      defoverridable run: 1

      def handle_prompt(_) do
        unquote(Macro.escape(opts))
        |> Keyword.get(:prompt, "")
      end

      defoverridable handle_prompt: 1
    end
  end

  @optional_callbacks handle_prompt: 1

  @typedoc """
  The state of the command
  """
  @type command_state :: term()

  @typedoc """
  A trimmed string of what the user typed
  """
  @type command :: String.t()

  @typedoc """
  options values for input type

  * `:hidden` - user input is not displayed
  * `:visible` - the user input is shown as the user types (default)
  """
  @type input_type :: :hidden | :visible

  @typedoc """
  Option values used to configure the command

  `:timeout` - defaults to 30 seconds
  """
  @type option :: {:timeout, timeout} | {:input_type, input_type}

  @typedoc """
  Options used by the command
  """
  @type options :: [option]

  @typep internal_state :: %{
           timeout: timeout,
           input_type: input_type,
           command_state: command_state
         }

  @default_timeout :timer.seconds(30)
  @default_input_type :visible

  @doc """
  (Optional Callback) Determines the prompt to use

  Returns t:String.t/0 or an IO List

  The handle prompt receives c:command_state/0 and returns a
  prompt suitable for printing. The default callback has no prompt
  """
  @callback handle_prompt(command_state) :: String.t() | [String.t()]

  @doc """
  Sets up the initial state of the command
  This callbaack receives the arguments that were passed to
  `Textophile.run/3`.

  Any return value other than `{:ok, state}` will result in an exception.
  """
  @callback init(term) :: {:ok, command_state} | {:error, term} | {:ok, command_state, continue: atom}

  @doc """
  Processes incoming commands

  When the user responds to a prompt the response is processed by
  `Textophile.handle_command/2`. The first argument is the
  command that the user sent in by typing and ending with a `\n`.

  The return value tells the prompt how to respond and updates the
  current state. Possible return values:

  * `{:ok, new_state}` - Causes the prompt to loop back around
  * `{:exit, response, new_state}` - Halts the returning of the prompt
  with the response as the status
  """
  @callback handle_command(String.t(), state) ::
              {:ok, state}
              | {:exit, term, state}
            when state: var

  @doc """
  Starts the command

  Returns the response from the last `Textophile.handle_command/2`
  that returns `{:exit, response, c:command_state/0}`.

  Inputs

  * c:module/0 - a module that implements the callbacks
  * c:term/0 - argument to be passed to `Textophile.init/1`
  * c:options/0 - (optional) default: `[]`
  """
  @spec run(module, term, options) :: term
  def run(module, args, options \\ []) do
    case apply(module, :init, [args]) do
      {:ok, command_state} ->
        _run(module, command_state, options)

      {:ok, command_state, continue: continue} ->
        command_state = apply(module, continue, [command_state])
        _run(module, command_state, options)

      error ->
        error
    end
  end

  defp _run(module, command_state, options) do
    internal_state = %{
      command_state: command_state,
      input_type: Keyword.get(options, :input_type, @default_input_type),
      timeout: Keyword.get(options, :timeout, @default_timeout)
    }

    loop(module, internal_state)
  end

  @spec loop(module(), internal_state) :: term
  defp loop(module, %{command_state: command_state} = internal_state) do
    apply(module, :handle_prompt, [command_state])
    |> prompt(internal_state)

    wait_for_command(module, internal_state)
  end

  @spec prompt(String.t() | [String.t()], internal_state) :: pid
  defp prompt(message, internal_state) do
    listener = self()

    spawn(fn ->
      send(listener, process_user_command(message, internal_state))
    end)
  end

  defp process_user_command(message, internal_state) do
    message
    |> get_input(internal_state)
    |> parse_command()
  rescue
    error ->
      {:command_error, error}
  end

  defp get_input(message, %{input_type: :visible}) do
    ensure_string_result(message, &IO.gets/1)
  end

  defp get_input(message, %{input_type: :hidden}) do
    ensure_string_result(message, &get_hidden_input/1)
  end

  def get_hidden_input(message) do
    IO.write(message)
    :io.get_password()
  end

  defp wait_for_command(
         module,
         %{command_state: command_state, timeout: timeout} = internal_state
       ) do
    receive do
      {:command_error, error} ->
        Logger.error(fn -> "An error caused #{__MODULE__} to crash #{inspect(error)}" end)
        next({:exit, "Command Error", internal_state}, module, internal_state)

      command ->
        apply(module, :handle_command, [command, command_state])
        |> next(module, internal_state)
    after
      timeout ->
        {:exit, :timeout, command_state}
    end
  end

  defp parse_command(input), do: String.trim_trailing(input)

  defp next({:ok, command_state}, module, internal_state) do
    loop(module, %{internal_state | command_state: command_state})
  end

  defp next({:exit, response, _}, _, _) do
    response
  end

  # `IO.gets/x` and the `:io` functions can return either a `String.t` or
  # a chardata. It depends on the configuration of `:io.setopts/x`. To keep
  # a consistent interface we want to always return a `String.t`.
  defp ensure_string_result(message, io_getter) do
    io_getter.(message) |> to_string()
  end
end
