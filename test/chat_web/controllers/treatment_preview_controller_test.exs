defmodule ChatWeb.TreatmentPreviewControllerTest do
  use ChatWeb.ConnCase, async: false

  alias Chat.Accounts.User
  alias Chat.Auth.Identity
  alias Chat.Repo
  alias Chat.Rooms
  alias Chat.Treatments
  alias ChatWeb.TreatmentPreviewController

  setup do
    Repo.insert!(%Chat.Treatments.Reason{
      code: "delay",
      label: "Atraso na entrega",
      active: true,
      sort_order: 1
    })

    :ok
  end

  describe "GET /api/treatments/:treatment_id/preview" do
    test "logistics_agent can preview an open/unassigned treatment and gets safe payload", %{
      conn: conn
    } do
      {:ok, owner} = Identity.sync_user(%{"sub" => "preview-owner"}, %{})
      agent = logistics_agent_fixture()

      {:ok, %{treatment: treatment}} =
        Treatments.open_structured_for_order(9_998_043_470, owner.id, %{
          reason_code: "delay",
          initial_description: "Customer is mad"
        })

      conn =
        conn
        |> assign(:current_user, agent)
        |> TreatmentPreviewController.show(%{"treatment_id" => treatment.id})

      assert response = json_response(conn, 200)
      assert response["treatment_id"] == treatment.id
      assert response["protocol"] == Treatments.protocol(treatment)
      assert response["order_id"] == 9_998_043_470
      assert response["reason"]["code"] == "delay"
      assert response["reason"]["label"] == "Atraso na entrega"
      assert response["initial_description"] == "Customer is mad"
      assert response["status"] == "open"
      assert Map.has_key?(response, "inserted_at")

      # Does not include room content
      refute Map.has_key?(response, "messages")
      refute Map.has_key?(response, "attachments")
      refute Map.has_key?(response, "room_history")
      refute Map.has_key?(response, "composer_data")

      # Customer summary
      assert response["customer_summary"]["customer_id"] == 491_564
      assert response["customer_summary"]["customer_name"] == "491564 - LORELEY ANDRADE"

      # Does not create room members
      refute Rooms.room_member?(agent.id, treatment.room_id)
    end

    test "preview includes customer_summary when order exists in Mock", %{conn: conn} do
      {:ok, owner} = Identity.sync_user(%{"sub" => "preview-owner-mock"}, %{})
      agent = logistics_agent_fixture()

      {:ok, %{treatment: treatment}} =
        Treatments.open_structured_for_order(9_998_043_469, owner.id, %{
          reason_code: "delay",
          initial_description: "Test"
        })

      conn =
        conn
        |> assign(:current_user, agent)
        |> TreatmentPreviewController.show(%{"treatment_id" => treatment.id})

      response = json_response(conn, 200)
      assert response["customer_summary"]["customer_id"] == 491_564
    end

    test "preview without customer summary when order not in Mock", %{conn: conn} do
      {:ok, owner} = Identity.sync_user(%{"sub" => "preview-owner-no-mock"}, %{})
      agent = logistics_agent_fixture()

      {:ok, %{treatment: treatment}} =
        Treatments.open_structured_for_order(111_111, owner.id, %{
          reason_code: "delay",
          initial_description: "Test"
        })

      conn =
        conn
        |> assign(:current_user, agent)
        |> TreatmentPreviewController.show(%{"treatment_id" => treatment.id})

      response = json_response(conn, 200)
      assert response["customer_summary"] == nil
    end

    test "commercial user gets 403", %{conn: conn} do
      {:ok, owner} = Identity.sync_user(%{"sub" => "preview-owner-commercial"}, %{})

      {:ok, %{treatment: treatment}} =
        Treatments.open_structured_for_order(9_998_043_470, owner.id, %{
          reason_code: "delay",
          initial_description: "Test"
        })

      conn =
        conn
        |> assign(:current_user, owner)
        |> TreatmentPreviewController.show(%{"treatment_id" => treatment.id})

      assert json_response(conn, 403) == %{"error" => "forbidden"}
    end

    test "treatment already assigned gets 403", %{conn: conn} do
      {:ok, owner} = Identity.sync_user(%{"sub" => "preview-owner-assigned"}, %{})
      agent = logistics_agent_fixture()

      {:ok, %{treatment: treatment}} =
        Treatments.open_structured_for_order(9_998_043_470, owner.id, %{
          reason_code: "delay",
          initial_description: "Test"
        })

      {:ok, _} = Treatments.assign_agent(treatment, agent)

      conn =
        conn
        |> assign(:current_user, agent)
        |> TreatmentPreviewController.show(%{"treatment_id" => treatment.id})

      assert json_response(conn, 403) == %{"error" => "forbidden"}
    end

    test "treatment in_progress gets 403", %{conn: conn} do
      {:ok, owner} = Identity.sync_user(%{"sub" => "preview-owner-in-progress"}, %{})
      agent = logistics_agent_fixture()

      {:ok, %{treatment: treatment}} =
        Treatments.open_structured_for_order(9_998_043_470, owner.id, %{
          reason_code: "delay",
          initial_description: "Test"
        })

      {:ok, treatment} = Treatments.assign_agent(treatment, agent)

      other_agent = logistics_agent_fixture()

      conn =
        conn
        |> assign(:current_user, other_agent)
        |> TreatmentPreviewController.show(%{"treatment_id" => treatment.id})

      assert json_response(conn, 403) == %{"error" => "forbidden"}
    end

    test "treatment resolved gets 403", %{conn: conn} do
      {:ok, owner} = Identity.sync_user(%{"sub" => "preview-owner-resolved"}, %{})
      agent = logistics_agent_fixture()

      {:ok, %{treatment: treatment}} =
        Treatments.open_structured_for_order(9_998_043_470, owner.id, %{
          reason_code: "delay",
          initial_description: "Test"
        })

      {:ok, treatment} = Treatments.assign_agent(treatment, agent)
      {:ok, _treatment} = Treatments.resolve(treatment, agent)

      other_agent = logistics_agent_fixture()

      conn =
        conn
        |> assign(:current_user, other_agent)
        |> TreatmentPreviewController.show(%{"treatment_id" => treatment.id})

      assert json_response(conn, 403) == %{"error" => "forbidden"}
    end

    test "treatment closed gets 403", %{conn: conn} do
      {:ok, owner} = Identity.sync_user(%{"sub" => "preview-owner-closed"}, %{})
      agent = logistics_agent_fixture()

      {:ok, %{treatment: treatment}} =
        Treatments.open_structured_for_order(9_998_043_470, owner.id, %{
          reason_code: "delay",
          initial_description: "Test"
        })

      {:ok, treatment} = Treatments.assign_agent(treatment, agent)
      {:ok, _treatment, :closed} = Treatments.close(treatment, agent)

      other_agent = logistics_agent_fixture()

      conn =
        conn
        |> assign(:current_user, other_agent)
        |> TreatmentPreviewController.show(%{"treatment_id" => treatment.id})

      assert json_response(conn, 403) == %{"error" => "forbidden"}
    end

    test "invalid treatment_id returns 400", %{conn: conn} do
      agent = logistics_agent_fixture()

      conn =
        conn
        |> assign(:current_user, agent)
        |> TreatmentPreviewController.show(%{"treatment_id" => "invalid-id"})

      assert json_response(conn, 400) == %{"error" => "bad_request"}
    end

    test "non-existent treatment_id returns 404", %{conn: conn} do
      agent = logistics_agent_fixture()

      conn =
        conn
        |> assign(:current_user, agent)
        |> TreatmentPreviewController.show(%{"treatment_id" => Ecto.UUID.generate()})

      assert json_response(conn, 404) == %{"error" => "not_found"}
    end

    test "requires authentication", %{conn: conn} do
      conn = get(conn, "/api/treatments/#{Ecto.UUID.generate()}/preview")
      assert response(conn, 401)
    end
  end

  defp logistics_agent_fixture do
    %User{}
    |> User.auth_changeset(%{
      email: "preview-agent-#{System.unique_integer([:positive])}@example.com",
      username: "preview-agent-#{System.unique_integer([:positive])}",
      role: "logistics_agent"
    })
    |> Repo.insert!()
  end
end
