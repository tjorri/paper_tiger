defmodule PaperTiger.Resources.SubscriptionPlanPriceTest do
  use ExUnit.Case, async: false

  import PaperTiger.Test
  import Plug.Conn
  import Plug.Test

  alias PaperTiger.Store.{Customers, Plans, Prices, Products}

  setup :checkout_paper_tiger

  setup do
    # Create a customer
    {:ok, _customer} =
      Customers.insert(%{
        created: PaperTiger.now(),
        email: "test@example.com",
        id: "cus_test",
        livemode: false,
        object: "customer"
      })

    # Create a product
    {:ok, _product} =
      Products.insert(%{
        active: true,
        created: PaperTiger.now(),
        id: "prod_test",
        livemode: false,
        name: "Test Product",
        object: "product"
      })

    # Create a price
    {:ok, _price} =
      Prices.insert(%{
        active: true,
        created: PaperTiger.now(),
        currency: "usd",
        id: "price_test_monthly",
        livemode: false,
        metadata: %{},
        nickname: nil,
        object: "price",
        product: "prod_test",
        recurring: %{interval: "month", interval_count: 1},
        type: "recurring",
        unit_amount: 1000
      })

    # Create a plan (legacy API)
    {:ok, _plan} =
      Plans.insert(%{
        active: true,
        amount: 2000,
        created: PaperTiger.now(),
        currency: "usd",
        id: "plan_test_monthly",
        interval: "month",
        interval_count: 1,
        livemode: false,
        metadata: %{},
        nickname: nil,
        object: "plan",
        product: "prod_test"
      })

    :ok
  end

  describe "POST /v1/subscriptions with price_id" do
    test "creates subscription with price ID" do
      conn =
        conn(:post, "/v1/subscriptions", %{
          customer: "cus_test",
          items: [%{price: "price_test_monthly", quantity: 1}]
        })
        |> put_req_header("authorization", "Bearer test_key")
        |> PaperTiger.Router.call([])

      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)

      assert response["object"] == "subscription"
      assert response["customer"] == "cus_test"
      assert response["status"] == "active"

      [item] = response["items"]["data"]
      assert item["price"]["id"] == "price_test_monthly"
      assert item["quantity"] == 1
    end
  end

  describe "POST /v1/subscriptions with plan_id (legacy)" do
    test "creates subscription with plan ID" do
      # Verify plan exists before making request
      assert {:ok, _plan} = Plans.get("plan_test_monthly")

      conn =
        conn(:post, "/v1/subscriptions", %{
          customer: "cus_test",
          items: [%{price: "plan_test_monthly", quantity: 1}]
        })
        |> put_req_header("authorization", "Bearer test_key")
        |> PaperTiger.Router.call([])

      if conn.status != 200 do
        IO.puts("ERROR Response: #{conn.resp_body}")
      end

      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)

      assert response["object"] == "subscription"
      assert response["customer"] == "cus_test"
      assert response["status"] == "active"

      [item] = response["items"]["data"]
      # Plan should be converted to price format
      assert item["price"]["id"] == "plan_test_monthly"
      assert item["price"]["unit_amount"] == 2000
      assert item["price"]["recurring"]["interval"] == "month"
      assert item["quantity"] == 1
    end
  end

  describe "POST /v1/subscriptions with invalid ID" do
    test "returns error for nonexistent price or plan" do
      conn =
        conn(:post, "/v1/subscriptions", %{
          customer: "cus_test",
          items: [%{price: "price_nonexistent", quantity: 1}]
        })
        |> put_req_header("authorization", "Bearer test_key")
        |> PaperTiger.Router.call([])

      assert conn.status == 404
      response = Jason.decode!(conn.resp_body)

      assert response["error"]["code"] == "resource_missing"
      assert response["error"]["message"] =~ "No such price: 'price_nonexistent'"
      assert response["error"]["param"] == "items[0][price]"
    end
  end

  describe "POST /v1/subscriptions/:id with price_id update" do
    setup do
      # Create initial subscription with price
      {:ok, subscription} =
        conn(:post, "/v1/subscriptions", %{
          customer: "cus_test",
          items: [%{price: "price_test_monthly", quantity: 1}]
        })
        |> put_req_header("authorization", "Bearer test_key")
        |> PaperTiger.Router.call([])
        |> Map.get(:resp_body)
        |> Jason.decode!()
        |> then(&{:ok, &1})

      {:ok, subscription: subscription}
    end

    test "an id-less new price adds an item and the existing item persists", %{subscription: subscription} do
      conn =
        conn(:post, "/v1/subscriptions/#{subscription["id"]}", %{
          items: [%{price: "plan_test_monthly", quantity: 2}]
        })
        |> put_req_header("authorization", "Bearer test_key")
        |> PaperTiger.Router.call([])

      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)

      # Stripe's update items are deltas: the unmentioned price_test_monthly
      # item survives, and the new price becomes a second item.
      items = response["items"]["data"]
      assert items |> Enum.map(& &1["price"]["id"]) |> Enum.sort() == ["plan_test_monthly", "price_test_monthly"]
      added = Enum.find(items, &(&1["price"]["id"] == "plan_test_monthly"))
      assert added["quantity"] == 2
    end
  end

  describe "mixed price and plan IDs" do
    test "creates subscription with multiple items using both price and plan IDs" do
      # Create another price
      {:ok, _price2} =
        Prices.insert(%{
          active: true,
          created: PaperTiger.now(),
          currency: "usd",
          id: "price_test_annual",
          livemode: false,
          metadata: %{},
          nickname: nil,
          object: "price",
          product: "prod_test",
          recurring: %{interval: "year", interval_count: 1},
          type: "recurring",
          unit_amount: 10_000
        })

      conn =
        conn(:post, "/v1/subscriptions", %{
          customer: "cus_test",
          items: [
            %{price: "price_test_annual", quantity: 1},
            %{price: "plan_test_monthly", quantity: 2}
          ]
        })
        |> put_req_header("authorization", "Bearer test_key")
        |> PaperTiger.Router.call([])

      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)

      items = response["items"]["data"]
      assert length(items) == 2

      # First item uses price ID
      assert Enum.at(items, 0)["price"]["id"] == "price_test_annual"
      assert Enum.at(items, 0)["quantity"] == 1

      # Second item uses plan ID (converted to price format)
      assert Enum.at(items, 1)["price"]["id"] == "plan_test_monthly"
      assert Enum.at(items, 1)["quantity"] == 2
    end
  end
end
