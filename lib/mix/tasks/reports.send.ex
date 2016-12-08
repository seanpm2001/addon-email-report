defmodule Mix.Tasks.Reports.Send do
  use Mix.Task

  require Logger

  alias Ecto.DateTime
  alias EmailReports.Repo

  import Mix.Ecto
  import Ecto.Query

  @shortdoc "Sends out all pending reports"

  def run(_) do
    {:ok, _pid, _} = ensure_started(EmailReports.Repo, [])
    for app <- [:dnsimple, :swoosh, :phoenix], do: Application.ensure_all_started(app)

    Repo.all(
      from s in EmailReports.Subscription,
       where: s.last_sent < ago(1, "month"),
       or_where: is_nil(s.last_sent),
       select: s
    )
    |> Enum.map(&send_mail/1)
  end

  defp send_mail(%EmailReports.Subscription{} = subscription) do
    dnsimple_account = account(subscription)
    |> EmailReports.Dnsimple.whoami
    |> Map.get(:account)

    Logger.info "Sending mail to subscription id: #{subscription.id} (#{dnsimple_account.email})"

    EmailReports.ReportEmail.simple(%{email: dnsimple_account.email, token: subscription.access_token})
    |> EmailReports.Mailer.deliver

    EmailReports.Subscription.changeset(subscription, %{last_sent: DateTime.utc})
    |> Repo.update
  end

  defp account(%EmailReports.Subscription{account_id: account_id, access_token: access_token}) do
    %{
      :dnsimple_access_token => access_token,
      :dnsimple_account_id => account_id,
    }
  end
end
