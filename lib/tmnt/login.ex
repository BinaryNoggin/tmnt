defmodule Tmnt.Login do
  @moduledoc "keeps us safe"
  use Textophile, timeout: :infinity

  defmodule User do
    defstruct name: nil

    def authenticate("lonestar", "amos") do
      {:ok, %__MODULE__{name: "amos"}}
    end

    def authenticate(_, _) do
      {:error, :bad_authentication}
    end

    def name(%__MODULE__{name: name}) do
      name
    end
  end

  def init([]) do
    {:ok, nil}
  end

  def handle_prompt(nil) do
    IO.write(IO.ANSI.clear())
    IO.write(IO.ANSI.home())
    "username: "
  end

  def handle_command(username, context) do
    case Tmnt.Login.Password.run(username) do
      {:ok, user} ->
        {:exit, user, context}
      {:error, :bad_authentication} ->
        IO.puts("Authentication Failed")
        Process.sleep(:timer.seconds(2))
        {:ok, context}
      {:exit, :timeout, _} ->
        {:ok, context}
    end
  end

  defmodule Password do
    use Textophile, input_type: :hidden, prompt: "password: ", timeout: :timer.seconds(10)

    defstruct tries: 0, username: nil

    def init(username) do
      {:ok, %__MODULE__{username: username}}
    end

    def handle_command(password, %{username: username, tries: 5}) do
      {:exit, Tmnt.Login.User.authenticate(password, username), nil}
    end

    def handle_command(password, %{username: username} = context) do
      case Tmnt.Login.User.authenticate(password, username) do
        {:ok, _} = response ->
          {:exit, response, nil}
        {:error, :bad_authentication} ->
          {:ok, retried(context)}
      end
    end

    def retried(%{tries: tries} = context) do
      %{context | tries: tries + 1}
    end
  end
end
