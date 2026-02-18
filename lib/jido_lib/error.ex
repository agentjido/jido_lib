defmodule JidoLib.Error do
  @moduledoc """
  Centralized error handling for JidoLib using Splode.

  Error classes are for classification; concrete `...Error` structs are for raising/matching.
  """

  use Splode,
    error_classes: [
      invalid: Invalid,
      execution: Execution,
      config: Config,
      internal: Internal
    ],
    unknown_error: __MODULE__.Internal.UnknownError

  # Error classes – classification only
  defmodule Invalid do
    @moduledoc "Invalid input error class for Splode."
    use Splode.ErrorClass, class: :invalid
  end

  defmodule Execution do
    @moduledoc "Execution error class for Splode."
    use Splode.ErrorClass, class: :execution
  end

  defmodule Config do
    @moduledoc "Configuration error class for Splode."
    use Splode.ErrorClass, class: :config
  end

  defmodule Internal do
    @moduledoc "Internal error class for Splode."
    use Splode.ErrorClass, class: :internal

    defmodule UnknownError do
      @moduledoc false
      defexception [:message, :details]
    end
  end

  # Concrete exception structs – raise/rescue these
  defmodule InvalidInputError do
    @moduledoc "Error for invalid input parameters."
    defexception [:message, :field, :value, :details]

    @type t :: %__MODULE__{
            message: String.t(),
            field: any(),
            value: any(),
            details: any()
          }

    @impl Exception
    def message(%__MODULE__{message: msg}), do: msg
  end

  defmodule ExecutionFailureError do
    @moduledoc "Error for runtime execution failures."
    defexception [:message, :details]

    @type t :: %__MODULE__{
            message: String.t(),
            details: any()
          }

    @impl Exception
    def message(%__MODULE__{message: msg}), do: msg
  end

  defmodule ConfigError do
    @moduledoc "Error for configuration issues."
    defexception [:message, :details]

    @type t :: %__MODULE__{
            message: String.t(),
            details: any()
          }

    @impl Exception
    def message(%__MODULE__{message: msg}), do: msg
  end

  # Helper functions
  @doc """
  Creates a validation error.

  ## Parameters

    * `message` - Error message
    * `details` - Map of error details (default: %{})

  ## Returns

    * `InvalidInputError` exception

  ## Examples

      iex> error = JidoLib.Error.validation_error("Invalid email", %{field: :email})
      iex> error.message
      "Invalid email"
  """
  @spec validation_error(String.t(), map()) :: InvalidInputError.t()
  def validation_error(message, details \\ %{}) do
    InvalidInputError.exception(Keyword.merge([message: message], Map.to_list(details)))
  end

  @doc """
  Creates an execution error.

  ## Parameters

    * `message` - Error message
    * `details` - Map of error details (default: %{})

  ## Returns

    * `ExecutionFailureError` exception
  """
  @spec execution_error(String.t(), map()) :: ExecutionFailureError.t()
  def execution_error(message, details \\ %{}) do
    ExecutionFailureError.exception(message: message, details: details)
  end

  @doc """
  Creates a configuration error.

  ## Parameters

    * `message` - Error message
    * `details` - Map of error details (default: %{})

  ## Returns

    * `ConfigError` exception
  """
  @spec config_error(String.t(), map()) :: ConfigError.t()
  def config_error(message, details \\ %{}) do
    ConfigError.exception(message: message, details: details)
  end
end
