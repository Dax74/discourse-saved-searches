require 'rails_helper'

describe Jobs::SavedSearchNotification do
  let(:user) { Fabricate(:user, trust_level: 1) }
  let(:tl2_user) { Fabricate(:user, trust_level: 2) }

  before do
    SearchIndexer.enable
  end

  it "does nothing if user has no saved searches" do
    expect {
      described_class.new.execute(user_id: user.id)
    }.to_not change { Topic.count }
  end

  context "with saved searches" do
    before do
      user.custom_fields["saved_searches"] = { "searches" => ["coupon", "discount"] }
      user.save!
    end

    it "doesn't create a PM for the user if no results are found" do
      expect {
        described_class.new.execute(user_id: user.id)
      }.to_not change { Topic.count }
    end

    context "first search" do
      context "with recent post" do
        let(:topic) { Fabricate(:topic, user: tl2_user) }
        let!(:post) { Fabricate(:post, topic: topic, user: tl2_user, raw: "Check out these coupon codes for cool things.") }

        it "creates a PM if recent results are found" do
          expect {
            described_class.new.execute(user_id: user.id)
          }.to change { Topic.where(subtype: TopicSubtype.system_message).count }.by(1)
        end

        it "does nothing if trust level is too low" do
          SiteSetting.saved_searches_min_trust_level = 2
          expect {
            described_class.new.execute(user_id: user.id)
          }.to_not change { Topic.count }
        end
      end

      it "doesn't create a PM if results are too old" do
        topic = Fabricate(:topic, user: tl2_user, created_at: 48.hours.ago)
        post = Fabricate(:post, topic: topic, user: tl2_user, raw: "Check out these coupon codes for cool things.", created_at: 48.hours.ago)
        expect {
          described_class.new.execute(user_id: user.id)
        }.to_not change { Topic.count }
      end

      it "doesn't notify for my own posts" do
        topic = Fabricate(:topic, user: user)
        post = Fabricate(:post, topic: topic, user: user, raw: "Check out these coupon codes for cool things.")
        expect {
          described_class.new.execute(user_id: user.id)
        }.to_not change { Topic.count }
      end
    end

    context "not the first search" do
      let(:topic) { Fabricate(:topic, user: tl2_user) }
      let!(:post)  {
        Fabricate(
          :post,
          topic: topic,
          user: tl2_user,
          raw: "Check out these coupon codes for cool things.")
      }

      before do
        described_class.new.execute(user_id: user.id)
      end

      it "doesn't notify about the same search results" do
        expect {
          described_class.new.execute(user_id: user.id)
        }.to_not change { Topic.where(subtype: TopicSubtype.system_message).count }
      end

      it "notifies about new results" do
        post2 = Fabricate(:post, topic: topic, user: tl2_user, raw: "Everyone loves a good discount.")
        expect {
          described_class.new.execute(user_id: user.id)
        }.to change { Topic.where(subtype: TopicSubtype.system_message).count }.by(1)
      end
    end
  end
end
