# Plugin's routes
# See: http://guides.rubyonrails.org/routing.html

resources :projects do
  resources :timeline, controller: 'timeline', as: 'timeline' do
    collection do
      post 'save_timeline_data', to: 'timeline#save_timeline_data'
      get  'load_timeline_data', to: 'timeline#load_timeline_data'
      post 'create_timeline',    to: 'timeline#create_timeline'
    end
  end
end
