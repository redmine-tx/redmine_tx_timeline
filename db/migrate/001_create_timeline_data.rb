class CreateTimelineData < ActiveRecord::Migration[6.1]
  def up
    if table_exists?(:roadmap_data)
      rename_table :roadmap_data, :timeline_data
    elsif !table_exists?(:timeline_data)
      create_table :timeline_data, options: 'ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci' do |t|
        t.integer :project_id, null: false
        t.string :name, null: false, default: 'Default', charset: 'utf8mb4', collation: 'utf8mb4_unicode_ci'
        t.text :description, charset: 'utf8mb4', collation: 'utf8mb4_unicode_ci'
        t.text :data, null: false, charset: 'utf8mb4', collation: 'utf8mb4_unicode_ci'
        t.boolean :is_active, default: true
        t.timestamps
      end

      add_foreign_key :timeline_data, :projects unless foreign_key_exists?(:timeline_data, :projects)
      add_index :timeline_data, [:project_id, :updated_at] unless index_exists?(:timeline_data, [:project_id, :updated_at])
      add_index :timeline_data, [:project_id, :is_active] unless index_exists?(:timeline_data, [:project_id, :is_active])
    end
  end

  def down
    if table_exists?(:timeline_data)
      rename_table :timeline_data, :roadmap_data
    end
  end
end
