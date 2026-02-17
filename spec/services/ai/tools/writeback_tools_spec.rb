require 'rails_helper'

RSpec.describe 'AI write-back tools' do
  let(:account) { create(:account) }
  let(:ai_user) { create(:user, account: account, role: :agent, is_ai_agent: true) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: ai_user) }
  let(:message) do
    create(
      :message,
      account: account,
      conversation: conversation,
      inbox: inbox,
      sender: conversation.contact,
      message_type: :incoming,
      private: false,
      content: 'hello'
    )
  end

  before do
    account.update!(
      ai_agent_user_id: ai_user.id,
      ai_tool_policy: {
        'enabled' => true,
        'allowed_tools' => {
          'conversation' => true,
          'crm' => true
        },
        'limits' => { 'max_tools_per_turn' => 3, 'max_total_steps' => 6 }
      }
    )
  end

  it 'adds and removes labels on conversation' do
    add_result = Ai::Tools::ToolRegistry.execute(
      account: account,
      conversation: conversation,
      message: message,
      tool_call: {
        name: 'add_conversation_label',
        arguments: { labels: ['vip', 'priority'] }.to_json
      }
    )

    expect(add_result[:content][:status]).to eq('ok')
    expect(conversation.reload.label_list).to include('vip', 'priority')

    remove_result = Ai::Tools::ToolRegistry.execute(
      account: account,
      conversation: conversation,
      message: message,
      tool_call: {
        name: 'remove_conversation_label',
        arguments: { label: 'vip' }.to_json
      }
    )

    expect(remove_result[:content][:status]).to eq('ok')
    expect(conversation.reload.label_list).to include('priority')
    expect(conversation.reload.label_list).not_to include('vip')
  end

  it 'creates contact note and private conversation note' do
    contact_note = Ai::Tools::ToolRegistry.execute(
      account: account,
      conversation: conversation,
      message: message,
      tool_call: {
        name: 'add_customer_note',
        arguments: { note: 'Musteri premium segmente alinacak.' }.to_json
      }
    )
    expect(contact_note[:content][:status]).to eq('ok')
    expect(conversation.contact.notes.last.content).to eq('Musteri premium segmente alinacak.')

    private_note = Ai::Tools::ToolRegistry.execute(
      account: account,
      conversation: conversation,
      message: message,
      tool_call: {
        name: 'add_conversation_private_note',
        arguments: { note: 'Satis ekibi follow-up yapsin.' }.to_json
      }
    )

    expect(private_note[:content][:status]).to eq('ok')
    note_message = conversation.messages.find(private_note[:content][:private_message_id])
    expect(note_message.private).to be(true)
    expect(note_message.content).to eq('Satis ekibi follow-up yapsin.')
  end

  it 'blocks crm tools when policy category is disabled' do
    account.update!(
      ai_tool_policy: {
        'enabled' => true,
        'allowed_tools' => {
          'conversation' => true,
          'crm' => false
        },
        'limits' => { 'max_tools_per_turn' => 3, 'max_total_steps' => 6 }
      }
    )

    result = Ai::Tools::ToolRegistry.execute(
      account: account,
      conversation: conversation,
      message: message,
      tool_call: {
        name: 'add_contact_note',
        arguments: { note: 'Not' }.to_json
      }
    )

    expect(result[:error]).to eq('tool_not_allowed')
  end
end
