Redmine::Plugin.register :redmine_tx_timeline do
  name 'Redmine Tx Timeline'
  author 'KiHyun Kang'
  description '프로젝트 타임라인 관리'
  version '0.0.1'

  requires_redmine_plugin :redmine_tx_0_base, version_or_higher: '0.0.1'

  menu :project_menu, :redmine_tx_timeline,
       { controller: 'timeline', action: 'index' },
       caption: '타임라인', param: :project_id,
       after: :redmine_tx_milestone, permission: :view_timeline

  project_module :redmine_tx_timeline do
    permission :view_timeline, { timeline: [:index] }
  end
end
