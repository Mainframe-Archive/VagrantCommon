##
# I created this to allow multiple vagrant files to share similar configuration
# 
# basically, I wanted stuff like nfs folder options to exist through multiple files and
# have default values be set before a user has a chance to set up configuration. And,
# I wanted to be able to package this up and easily create a base box without having to
# configure much of anything
# 
# @example
#   config = Montage::Vagrant.configure #get the singleton configuration from any Vagrantfile
# 
# @author Jay Marcyes
##
module Vagrant extend self

  class Configuration

    attr_accessor :config

    def self.get
    
      @config ||= Vagrant::Configuration.new
    
    end
    
  end

  class Configuration

    # needed to make sure all methods can be called like this: Module.method outside
    # http://stackoverflow.com/questions/2353498/is-extend-self-the-same-as-module-function
    # http://www.ruby-doc.org/docs/ProgrammingRuby/html/ref_c_module.html#Module.module_function
    # module_function
  
    ##
    # set to true or false if nfs is needed to make shared folders work
    #
    # @link http://vagrantup.com/docs/nfs.html
    # @var  boolean
    ##
    attr_accessor :nfs_on
    
    ##
    # will hold the configuration fields that will be passed to the vagrant configs
    #
    # @var  hash
    ##
    attr_accessor :config_field_map
    
    ##
    # holds the chef fields that will be set if a chef recipe is added
    #
    # @var  hash
    ##
    attr_accessor :chef_field_map
    
    ##
    # hold the chef recipes
    #
    # @var  hash
    ##
    attr_accessor :chef_recipe_map
    
    def initialize
      
      @nfs_on = nil
      @config_field_map = {}
      @chef_field_map = {}
      @chef_recipe_map = {}
      
    end
    
    ##
    # set a configuration field
    #
    # @param  string  k the field
    # @param  mixed v the k value
    ##
    def setField(k,v)
    
      # since a field has never been set, configure block that will do all the heavy 
      # lifting once this class is completely populated, this block won't be ran until
      # all the vagrant files have been loaded
      if @config_field_map.count <= 0
      
        ::Vagrant::Config.run do |config|
          
          setConfigFields(config)
          setChefFields(config)
          
        end
      
      end
    
      @config_field_map[k] ||= []
      @config_field_map[k] << v
    
    end
    
    ##
    # forward a port
    #
    # @param  string  label the name you want to give to this port forwarding
    # @param  integer vm_port the port you want to forward on the vm (eg, 80, or 443)
    # @param  integer main_port the port the vm_port will map to this port (eg, 8080)
    ##
    def forwardPort(label,vm_port,main_port)
    
      setField("forward_port",[label,vm_port,main_port])
    
    end
    
    ##
    # forward a port
    #
    # @since  1-26-12
    # @param  string  box_name  the name of the box you want to use
    # @param  string  box_url the url where the box can be remotely fetched if not available locally
    ##
    def setBox(box_name,box_url = "")
    
      setField("box",box_name)
      setField("box_url",box_url)
    
    end
    
    ##
    # share a folder with the vm box
    #
    # @param  string  label the name you want to give to this port forwarding
    # @param  string  vm_path the path the folder will have on the vm box
    # @param  string  main_path the path the folder will have on the host machine
    # @param  hash  options any options you want to set
    ##
    def shareFolder(label,vm_path,main_path,options = {})
      
      if @nfs_on.nil?
      
        # Switching to nfs for only those who want it
        # thanks http://www.jedi.be/blog/2011/03/28/using-vagrant-as-a-team/
        # http://vagrantup.com/docs/nfs.html
        @nfs_on = RUBY_PLATFORM.include?('darwin')
        # http://www.ruby-forum.com/topic/86488
        # mac: puts RUBY_PLATFORM => i686-darwin10
        # windows: puts RUBY_PLATFORM => i386-mingw32
      
        # do this the first time nfs is checked  
        if(@nfs_on)
      
          # Assign this VM to a host only network IP, allowing you to access it via the IP.
          setField("network","33.33.33.10")
          
        end
      
      end
      
      # do this every time a folder is shared and nfs is on
      if(@nfs_on)
      
        options.merge({:nfs => true})
      
      end
      
      setField("share_folder",[label,vm_path,main_path,options])
    
    end
    
    ##
    # set a chef field
    #
    # @param  string  k the field
    # @param  mixed v the k value
    ##
    def setChefField(k,v)
    
      @chef_field_map[k] ||= []
      @chef_field_map[k] << v
    
    end
    
    ##
    # add a chef solo cookbook path
    #
    # @param  string  cookbook_path the local machine path
    ##
    def addCookbookPath(cookbook_path)
  
      # canary
      raise ArgumentError, 'cookbook_path does not exist' unless File.directory?(cookbook_path)
      
      setChefField("cookbooks_path",cookbook_path)
    
    end
    
    ##
    # add a chef recipe
    #
    # @param  string  recipe  the name of the recipe
    # @param  hash  json  any custom configuration you want to pass to the recipe
    ##
    def addRecipe(recipe,json = {})
    
      if @chef_recipe_map.has_key?(recipe)
      
        @chef_recipe_map[recipe].merge!(json)
      
      else
    
        @chef_recipe_map[recipe] = json
        
      end
    
    end
    
    private
    
    ##
    # actually pass the chef fields that were set in this class to the vagrant config
    #
    # @param  Config::Top config  the configuration object
    ##
    def setChefFields(config)
    
      # canary
      return if @chef_recipe_map.count <= 0
      
      config.vm.provision :chef_solo do |chef|
      
        # https://github.com/mitchellh/vagrant/pull/303
        # http://kief.com/node/76
        chef.log_level = :debug
        
        @chef_field_map.each do |k,v|
          
          configureField(chef,k,v)
        
        end
        
        @chef_recipe_map.each do |recipe,json|
          
          chef.json.merge!(json)
          chef.add_recipe(recipe)
        
        end
        
      end
        
    end
    
    ##
    # this is the common method that will set the k field of obj with the value v
    #
    # @param  object  obj the object whose field will be set
    # @param  string  k the field
    # @param  string  v the field k's value
    ##
    def configureField(obj,k,v)
    
      # http://www.khelll.com/blog/ruby/ruby-dynamic-method-calling/
      method_name = "#{k}="
      
      if obj.respond_to?(method_name)
      
        v.each do |val| obj.send(method_name,val) end
        
      else
      
        # http://stackoverflow.com/questions/5119352/achieving-call-user-func-array-in-ruby
        v.each do |val| obj.send(k,*val) end
      
      end
      
      # print "#{k} = #{v}\r\n"
    
    end
    
    ##
    # actually pass the config fields that were set in this class to the vagrant config
    #
    # @param  Config::Top config  the configuration object
    ##
    def setConfigFields(config)
    
      # load all the previsouly set configuration variables
      @config_field_map.each do |k,v|
      
        configureField(config.vm,k,v)
      
      end
    
    end
  
  end
  
end