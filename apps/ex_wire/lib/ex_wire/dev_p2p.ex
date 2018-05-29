defmodule ExWire.DEVp2p do
  @moduledoc """
  Functions that deal directly with the DEVp2p Wire Protocol.

  For more information, please see:
  https://github.com/ethereum/wiki/wiki/%C3%90%CE%9EVp2p-Wire-Protocol
  """

  alias ExWire.{Config, Packet}

  defmodule Session do
    @moduledoc """
      Module to hold struct for a DEVp2p Wire Protocol session.
      The session should be active when `Hello` messages have been exchanged.

      See https://github.com/ethereum/wiki/wiki/%C3%90%CE%9EVp2p-Wire-Protocol#session-management
    """

    alias ExWire.Packet.Hello

    @type handshake_status :: boolean | ExWire.Packet.Hello.t()
    @type t :: %Session{handshake_sent: handshake_status, handshake_received: handshake_status}

    defstruct handshake_sent: false, handshake_received: false

    @doc """
    Checks whether or not the session is active.

    A session is only active if the handshake is complete and if there are overlapping capabilities, meaning
    that some of the sub-protocols are the same (e.g. eth 62)

    ## Examples

        iex> handshake_received = %ExWire.Packet.Hello{caps: [{"eth", 62}]}
        iex> handshake_sent = %ExWire.Packet.Hello{caps: [{"eth", 62}]}
        iex> ExWire.DEVp2p.Session.active?(%ExWire.DEVp2p.Session{handshake_received: handshake_received, handshake_sent: handshake_sent})
        true
    """
    @spec active?(t) :: boolean()
    def active?(%Session{handshake_received: false}), do: false
    def active?(%Session{handshake_sent: false}), do: false

    def active?(%Session{handshake_sent: %Hello{}, handshake_received: %Hello{}} = session) do
      compatible_capabilities?(session)
    end

    @spec disconnect(t) :: Session.t()
    def disconnect(session = %Session{}) do
      %{session | handshake_sent: false, handshake_received: false}
    end

    @spec compatible_capabilities?(t) :: boolean()
    def compatible_capabilities?(session = %Session{}) do
      %Session{handshake_received: handshake_received, handshake_sent: handshake_sent} = session

      intersection =
        MapSet.intersection(
          to_mapset(handshake_received.caps),
          to_mapset(handshake_sent.caps)
        )

      !Enum.empty?(intersection)
    end

    defp to_mapset(list) do
      Enum.into(list, MapSet.new())
    end
  end

  @doc """
  Convenience function to create an `ExWire.DEVp2p.Session` struct
  """
  @spec init_session :: Session.t()
  def init_session do
    %Session{}
  end

  @doc """
  Function to create a DEVp2p struct needed for a protocol handshake. This
  should be an `ExWire.Packet.Hello` struct with the appropriate values filled in.
  """
  @spec generate_handshake :: Packet.Hello.t()
  def generate_handshake do
    %Packet.Hello{
      p2p_version: Config.p2p_version(),
      client_id: Config.client_id(),
      caps: Config.caps(),
      listen_port: Config.listen_port(),
      node_id: Config.node_id()
    }
  end

  @doc """
  Function to update `ExWire.DEVp2p.Session` when a handshake is sent. The
  handshake should be an `ExWire.Packet.Hello` that we have sent to a peer.
  """
  @spec handshake_sent(Session.t(), Packet.Hello.t()) :: Session.t()
  def handshake_sent(session, hello = %Packet.Hello{}) do
    %{session | handshake_sent: hello}
  end

  @doc """
  Function to update `ExWire.DEVp2p.Session` when a handshake is received. The
  handshake should be an `ExWire.Packet.Hello` that we have received from a peer.
  """
  @spec handshake_received(Session.t(), Packet.Hello.t()) :: Session.t()
  def handshake_received(session, hello = %Packet.Hello{}) do
    %{session | handshake_received: hello}
  end

  @doc """
  Function to check whether or not a `ExWire.DEVp2p.Session` is active. See
  `ExWire.DEVp2p.Session.active?/1` for more information.
  """
  @spec session_active?(Session.t()) :: boolean()
  def session_active?(session), do: Session.active?(session)

  @spec session_compatible?(Session.t()) :: boolean()
  def session_compatible?(session), do: Session.compatible_capabilities?(session)

  @doc """
  Function to handles other messages related to the DEVp2p protocol that a peer
  sends. The messages could be `ExWire.Packet.Disconnect`, `ExWire.Packet.Ping`,
  or `ExWire.Packet.Pong`.

  An `ExWire.DEVp2p.Session` is required as the first argument in order to
  properly update the session based on the message received.
  """
  @spec handle_message(Session.t(), struct()) ::
          {:error, :handshake_incomplete, Session.t()}
          | {:ok, ExWire.Packet.handle_response(), Session.t()}
  def handle_message(session, message) do
    if session_active?(session) do
      response = generate_response(message)
      new_session = update_session(session, message)
      {:ok, response, new_session}
    else
      {:error, :handshake_incomplete, session}
    end
  end

  @spec update_session(Session.t(), struct()) :: Session.t()
  defp update_session(session, %Packet.Disconnect{}) do
    Session.disconnect(session)
  end

  defp update_session(session, _message), do: session

  @spec generate_response(struct()) :: ExWire.Packet.handle_response()
  defp generate_response(%Packet.Ping{} = ping), do: Packet.Ping.handle(ping)

  defp generate_response(%Packet.Disconnect{} = disconnect),
    do: Packet.Disconnect.handle(disconnect)
end
